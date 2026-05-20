#!/usr/bin/env python3
"""
Cute Face Display for RK3588S Smart Car
800x480 HDMI full-screen display showing animated cute robot faces.

Uses pygame for hardware-accelerated rendering on RK3588S Mali GPU.
Can be run standalone or controlled via Flask app.

Auto-detects display backend:
- X11: when running on KDE Plasma / desktop environment
- KMS/DRM: when running on pure framebuffer (no X11)
- Windowed: fallback for headless / testing

Faces: neutral, happy, sad, angry, surprised, sleepy, love, cool
"""

import os
import sys
import math
import threading
import time
from typing import Optional, List, Tuple

# Auto-detect display driver
# If DISPLAY is set, we're on a desktop (KDE/GNOME/X11) -> use x11
# Otherwise try kmsdrm for direct HDMI
def _auto_detect_display():
    if os.environ.get('DISPLAY'):
        os.environ['SDL_VIDEODRIVER'] = 'x11'
        print(f"[FaceDisplay] DISPLAY={os.environ['DISPLAY']} detected, using x11")
    else:
        # Try to auto-detect active X11 session (e.g., SSH start but KDE already running)
        for display_num in ['0', '1', '2']:
            if os.path.exists(f'/tmp/.X11-unix/X{display_num}'):
                os.environ['DISPLAY'] = f':{display_num}'
                os.environ['SDL_VIDEODRIVER'] = 'x11'
                print(f"[FaceDisplay] Auto-detected DISPLAY=:{display_num} from /tmp/.X11-unix/X{display_num}")
                break
    if os.environ.get('SDL_VIDEODRIVER') == 'x11' or os.environ.get('DISPLAY'):
        # Force pure software rendering — disable SDL's OpenGL framebuffer acceleration
        os.environ['SDL_FRAMEBUFFER_ACCELERATION'] = '0'
        os.environ['SDL_RENDER_DRIVER'] = 'software'
        os.environ['SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR'] = '1'
        print("[FaceDisplay] Forced SOFTWARE render: SDL_FRAMEBUFFER_ACCELERATION=0, SDL_RENDER_DRIVER=software")
    elif os.path.exists('/dev/dri/card0'):
        os.environ['SDL_VIDEODRIVER'] = 'kmsdrm'
        print("[FaceDisplay] No X11 found, falling back to KMS/DRM")
    else:
        print("[FaceDisplay] No display driver available (no X11, no KMS/DRM)")

_auto_detect_display()
# Fallbacks: 'fbcon' for pure framebuffer, 'dummy' for headless

import pygame


class CuteFaceDisplay:
    """
    800x480 LED matrix pixel face display.
    Fullscreen animated robot face with blinking and emotion transitions.
    Sci-fi HUD style: dark blue-black background + cyan glowing pixel dots.
    """

    WIDTH = 800
    HEIGHT = 480
    FPS = 30

    # LED Grid config
    GRID_COLS = 40
    GRID_ROWS = 24
    CELL_W = WIDTH / GRID_COLS   # 20
    CELL_H = HEIGHT / GRID_ROWS  # 20
    DOT_SIZE = 14                # LED pixel size (smaller than cell for grid gap)

    # Colors
    BG_COLOR = (3, 7, 18)          # Deep blue-black
    GRID_COLOR = (10, 21, 37)      # Dark grid cell background
    LED_COLOR = (0, 229, 255)     # Cyan glow (#00e5ff)
    LED_LOVE = (255, 102, 178)    # Pink for love
    LED_ANGRY = (255, 51, 102)    # Red for angry
    LED_SLEEPY = (0, 184, 212)   # Dim cyan for sleepy
    BORDER_COLOR = (0, 229, 255)  # Cyan border

    def __init__(self):
        self.screen: Optional[pygame.Surface] = None
        self.running = False
        self.render_thread: Optional[threading.Thread] = None
        self.lock = threading.Lock()

        # Current emotion
        self._emotion = "neutral"
        self._target_emotion = "neutral"
        self._emotion_transition = 0.0

        # Animation state
        self._blink_state = 0.0  # 0=open, 1=closed
        self._blink_timer = 0.0
        self._next_blink = 2.5 + (hash(id(self)) % 100) / 50.0
        self._time = 0.0

        # Eye tracking target (normalized -1 to 1)
        self._eye_target_x = 0.0
        self._eye_target_y = 0.0

        # Pre-rendered glow surface to avoid per-frame allocation
        self._glow_surf: Optional[pygame.Surface] = None

    def init(self) -> bool:
        """Initialize pygame and enter fullscreen mode"""
        try:
            print("[FaceDisplay] pygame.init() starting...")
            pygame.init()
            pygame.display.init()
            print(f"[FaceDisplay] pygame display driver: {pygame.display.get_driver()}")

            # Detect display mode
            is_x11 = os.environ.get('SDL_VIDEODRIVER') == 'x11' or bool(os.environ.get('DISPLAY'))
            
            if is_x11:
                # FULLSCREEN + NOFRAME hides KDE taskbar; software render avoids Mali GL conflict
                os.environ['SDL_VIDEO_WINDOW_POS'] = '0,0'
                os.environ['SDL_VIDEO_CENTERED'] = '0'
                print(f"[FaceDisplay] Creating X11 FULLSCREEN+NOFRAME window {self.WIDTH}x{self.HEIGHT} (software render)")
                self.screen = pygame.display.set_mode(
                    (self.WIDTH, self.HEIGHT),
                    pygame.FULLSCREEN | pygame.NOFRAME
                )
                print("[FaceDisplay] X11 fullscreen surface created OK")
                print(f"[FaceDisplay] Surface type: {type(self.screen)}, depth={self.screen.get_bitsize() if self.screen else 'None'}")
                try:
                    info = pygame.display.Info()
                    print(f"[FaceDisplay] Display info: hw={info.hw}, wm={info.wm}")
                except Exception as ie:
                    print(f"[FaceDisplay] Display info error: {ie}")
            else:
                # Try KMS/DRM first (best for RK3588S direct HDMI)
                print("[FaceDisplay] Trying KMS/DRM fullscreen...")
                try:
                    self.screen = pygame.display.set_mode(
                        (self.WIDTH, self.HEIGHT),
                        pygame.FULLSCREEN | pygame.DOUBLEBUF | pygame.HWSURFACE
                    )
                    print("[FaceDisplay] Running in KMS/DRM fullscreen mode")
                except Exception as kmse:
                    print(f"[FaceDisplay] KMS/DRM failed ({kmse}), trying windowed fallback...")
                    self.screen = pygame.display.set_mode((self.WIDTH, self.HEIGHT))
                    print("[FaceDisplay] Running in windowed fallback mode")

            if self.screen is None:
                raise RuntimeError("pygame.display.set_mode returned None")

            # Pre-render glow overlay (circular soft glow behind each LED)
            glow_r = self.DOT_SIZE // 2 + 6
            self._glow_surf = pygame.Surface((glow_r * 2, glow_r * 2), pygame.SRCALPHA)
            # Draw radial gradient-like glow using concentric circles
            for radius, alpha in [(glow_r, 30), (glow_r - 2, 50), (glow_r - 4, 80)]:
                pygame.draw.circle(self._glow_surf, (0, 229, 255, alpha), (glow_r, glow_r), radius)

            pygame.mouse.set_visible(False)
            self.running = True
            self.render_thread = threading.Thread(target=self._render_loop, daemon=True)
            self.render_thread.start()
            print(f"[FaceDisplay] Started {self.WIDTH}x{self.HEIGHT} pixel face display")
            return True
        except Exception as e:
            print(f"[FaceDisplay] Failed to init: {e}")
            self.running = False
            self.screen = None
            return False

    def stop(self):
        """Stop display and cleanup pygame"""
        self.running = False
        if self.render_thread:
            self.render_thread.join(timeout=2.0)
        pygame.quit()
        print("[FaceDisplay] Stopped")

    def set_emotion(self, emotion: str):
        """Set face emotion"""
        valid = ["neutral", "happy", "sad", "angry", "surprised", "sleepy", "love", "cool"]
        if emotion in valid:
            with self.lock:
                self._target_emotion = emotion

    def set_eye_target(self, x: float, y: float):
        """Set eye gaze target (-1 to 1)"""
        with self.lock:
            self._eye_target_x = max(-1, min(1, x))
            self._eye_target_y = max(-1, min(1, y))

    def _render_loop(self):
        """Main rendering loop running in background thread"""
        clock = pygame.time.Clock()
        frame_count = 0
        last_log = time.time()
        print("[FaceDisplay] _render_loop started")
        while self.running:
            try:
                dt = clock.tick(self.FPS) / 1000.0
                self._time += dt
                self._update_animations(dt)
                self._draw_frame()
                # Use update() instead of flip() to avoid GL swap chain
                pygame.display.update()
                frame_count += 1
                if time.time() - last_log >= 5.0:
                    print(f"[FaceDisplay] Rendering at ~{frame_count/5:.1f} fps ({self._emotion})")
                    frame_count = 0
                    last_log = time.time()

                # Process quit events
                for event in pygame.event.get():
                    if event.type == pygame.QUIT:
                        self.running = False
                    elif event.type == pygame.KEYDOWN:
                        if event.key == pygame.K_ESCAPE or event.key == pygame.K_q:
                            self.running = False
            except Exception as e:
                print(f"[FaceDisplay] Render loop error: {e}")
                import traceback
                traceback.print_exc()
                time.sleep(0.5)

    def _update_animations(self, dt: float):
        """Update blink and transition animations"""
        with self.lock:
            # Emotion transition
            if self._target_emotion != self._emotion:
                self._emotion_transition += dt * 3.0
                if self._emotion_transition >= 1.0:
                    self._emotion = self._target_emotion
                    self._emotion_transition = 0.0
            else:
                self._emotion_transition = 0.0

            # Blink logic
            self._blink_timer += dt
            if self._blink_timer >= self._next_blink:
                # Start blink
                self._blink_state = min(1.0, self._blink_state + dt * 15.0)
                if self._blink_state >= 1.0:
                    # Blink done, schedule next
                    self._blink_state = 0.0
                    self._blink_timer = 0.0
                    self._next_blink = 2.0 + (self._time * 1000 % 100) / 100.0 * 2.0
            else:
                self._blink_state = max(0.0, self._blink_state - dt * 15.0)

    # ===================== LED Matrix Drawing =====================

    def _pixel_rect(self, left: int, top: int, w: int, h: int) -> List[Tuple[int, int]]:
        """Return list of (col, row) for a filled rectangle"""
        return [(c, r) for c in range(left, left + w) for r in range(top, top + h)]

    def _pixel_line(self, x0: int, y0: int, x1: int, y1: int) -> List[Tuple[int, int]]:
        """Bresenham line on pixel grid"""
        points = []
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            points.append((x0, y0))
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy
        return points

    def _draw_led_pixel(self, col: int, row: int, color: Tuple[int, int, int], glow: bool = True):
        """Draw a single LED pixel with optional glow"""
        if not self.screen:
            return
        x = int(col * self.CELL_W + (self.CELL_W - self.DOT_SIZE) / 2)
        y = int(row * self.CELL_H + (self.CELL_H - self.DOT_SIZE) / 2)
        ds = self.DOT_SIZE

        if glow and self._glow_surf:
            gr = self._glow_surf.get_width() // 2
            self.screen.blit(self._glow_surf, (x + ds // 2 - gr, y + ds // 2 - gr))

        # Main LED body
        pygame.draw.rect(self.screen, color, (x, y, ds, ds), border_radius=2)
        # Inner highlight
        bright = tuple(min(255, c + 80) for c in color)
        pygame.draw.rect(self.screen, bright, (x + 3, y + 3, ds - 6, ds - 6), border_radius=1)

    def _draw_pixel_border(self):
        """Draw dashed LED border around screen edge"""
        color = self.BORDER_COLOR
        cmax = self.GRID_COLS - 1
        rmax = self.GRID_ROWS - 1
        # Top & Bottom
        for c in range(self.GRID_COLS):
            if c % 2 == 0:
                self._draw_led_pixel(c, 0, color, glow=False)
                self._draw_led_pixel(c, rmax, color, glow=False)
        # Left & Right
        for r in range(self.GRID_ROWS):
            if r % 2 == 0:
                self._draw_led_pixel(0, r, color, glow=False)
                self._draw_led_pixel(cmax, r, color, glow=False)
        # Rounded corners: extra bright pixels
        corners = [(1, 1), (cmax - 1, 1), (1, rmax - 1), (cmax - 1, rmax - 1)]
        for cc, rr in corners:
            self._draw_led_pixel(cc, rr, color, glow=True)

    def _draw_pixel_grid(self):
        """Draw dark grid background (dim LED cells)"""
        for c in range(self.GRID_COLS):
            for r in range(self.GRID_ROWS):
                self._draw_led_pixel(c, r, self.GRID_COLOR, glow=False)

    def _get_eye_pixels(self, emotion: str, blink: float) -> List[Tuple[int, int]]:
        """Get eye pixel coordinates for emotion"""
        if blink > 0.5:
            # Closed eyes: thin horizontal lines
            return self._pixel_rect(8, 10, 5, 1) + self._pixel_rect(27, 10, 5, 1)

        if emotion == "neutral":
            return self._pixel_rect(8, 8, 5, 5) + self._pixel_rect(27, 8, 5, 5)

        elif emotion == "happy":
            # Chevron up ^^
            left = [(7, 12), (8, 11), (9, 10), (10, 9), (11, 10), (12, 11), (13, 12)]
            right = [(26, 12), (27, 11), (28, 10), (29, 9), (30, 10), (31, 11), (32, 12)]
            return left + right

        elif emotion == "sad":
            # vv (inverted chevron) - droopy eyes
            left = [(7, 9), (8, 10), (9, 11), (10, 12), (11, 11), (12, 10), (13, 9)]
            right = [(26, 9), (27, 10), (28, 11), (29, 12), (30, 11), (31, 10), (32, 9)]
            return left + right

        elif emotion == "angry":
            # Angry: block eyes with inner "x" detail (small cross)
            base = self._pixel_rect(8, 8, 5, 5) + self._pixel_rect(27, 8, 5, 5)
            # Small cross in each eye center
            cross_l = self._pixel_line(9, 9, 11, 11) + self._pixel_line(11, 9, 9, 11)
            cross_r = self._pixel_line(28, 9, 30, 11) + self._pixel_line(30, 9, 28, 11)
            return base + cross_l + cross_r

        elif emotion == "surprised":
            return self._pixel_rect(7, 7, 7, 7) + self._pixel_rect(26, 7, 7, 7)

        elif emotion == "sleepy":
            return self._pixel_rect(8, 10, 5, 1) + self._pixel_rect(27, 10, 5, 1)

        elif emotion == "love":
            # Heart shape eyes (pink)
            left = [(8, 9), (9, 8), (10, 9), (9, 10), (10, 11), (11, 10), (11, 9), (12, 10)]
            right = [(27, 9), (28, 8), (29, 9), (28, 10), (29, 11), (30, 10), (30, 9), (31, 10)]
            return left + right

        elif emotion == "cool":
            return self._pixel_rect(7, 9, 6, 3) + self._pixel_rect(26, 9, 6, 3)

    def _get_brow_pixels(self, emotion: str) -> List[Tuple[int, int]]:
        """Get eyebrow pixel coordinates"""
        if emotion == "happy":
            # Happy: gentle raised brows
            left = self._pixel_line(6, 5, 13, 3)
            right = self._pixel_line(26, 3, 33, 5)
            return left + right
        elif emotion == "angry":
            # Angry: thick angry slanted brows
            left = self._pixel_line(5, 5, 14, 9)
            right = self._pixel_line(25, 9, 34, 5)
            return left + right
        elif emotion == "sad":
            # Sad: inverted (drooping) brows
            left = self._pixel_line(6, 6, 13, 4)
            right = self._pixel_line(26, 4, 33, 6)
            return left + right
        return []

    def _get_mouth_pixels(self, emotion: str) -> List[Tuple[int, int]]:
        """Get mouth pixel coordinates"""
        if emotion == "neutral":
            return self._pixel_rect(16, 17, 9, 2)

        elif emotion == "happy":
            # Smile arc
            return [(14, 16), (15, 17), (16, 18), (17, 18), (18, 19), (19, 19),
                    (20, 19), (21, 19), (22, 18), (23, 18), (24, 17), (25, 16)]

        elif emotion == "sad":
            # Inverted smile (frown arc)
            return [(14, 19), (15, 18), (16, 17), (17, 17), (18, 16), (19, 16),
                    (20, 16), (21, 16), (22, 17), (23, 17), (24, 18), (25, 19)]

        elif emotion == "angry":
            return self._pixel_rect(15, 18, 10, 2)

        elif emotion == "surprised":
            # Open O mouth (small square with hollow center)
            outer = self._pixel_rect(17, 16, 6, 6)
            inner = self._pixel_rect(18, 17, 4, 4)
            # Subtract inner by filtering
            outer_set = set(outer)
            inner_set = set(inner)
            return list(outer_set - inner_set)

        elif emotion == "sleepy":
            return self._pixel_rect(17, 17, 7, 1)

        elif emotion == "love":
            # Gentle smile
            return [(15, 17), (16, 18), (17, 18), (18, 19), (19, 19),
                    (20, 19), (21, 19), (22, 18), (23, 18), (24, 17)]

        elif emotion == "cool":
            return self._pixel_rect(16, 17, 9, 1)

        return []

    def _get_cheek_pixels(self, emotion: str) -> List[Tuple[int, int]]:
        """Get decorative cheek pixels (hearts, etc.)"""
        if emotion == "angry":
            # Heart on left cheek (red, small)
            return [(3, 14), (4, 13), (5, 14), (4, 15)]
        elif emotion == "love":
            # Hearts on both cheeks (pink)
            left = [(3, 14), (4, 13), (5, 14), (4, 15)]
            right = [(34, 14), (35, 13), (36, 14), (35, 15)]
            return left + right
        return []

    def _get_bridge_pixels(self, emotion: str) -> List[Tuple[int, int]]:
        """Sunglasses bridge for cool mode"""
        if emotion == "cool":
            return self._pixel_rect(13, 10, 14, 1)
        return []

    def _emotion_color(self, emotion: str) -> Tuple[int, int, int]:
        """LED color per emotion"""
        if emotion == "sleepy":
            return self.LED_SLEEPY
        elif emotion == "angry":
            return self.LED_ANGRY
        elif emotion == "love":
            return self.LED_LOVE
        return self.LED_COLOR

    def _draw_frame(self):
        """Draw the complete LED matrix face frame"""
        if not self.screen:
            return

        screen = self.screen
        emotion = self._emotion
        blink = self._blink_state
        color = self._emotion_color(emotion)

        # 1. Background
        screen.fill(self.BG_COLOR)

        # 2. Dark grid background
        self._draw_pixel_grid()

        # 3. Dashed LED border
        self._draw_pixel_border()

        # 4. Collect all active pixels for this emotion
        pixels = []
        pixels += self._get_eye_pixels(emotion, blink)
        pixels += self._get_brow_pixels(emotion)
        pixels += self._get_mouth_pixels(emotion)
        pixels += self._get_cheek_pixels(emotion)
        pixels += self._get_bridge_pixels(emotion)

        # Apply slight eye gaze tracking offset
        gaze_c = int(self._eye_target_x * 1.5)
        gaze_r = int(self._eye_target_y * 1.5)
        # Only offset eye pixels (rough filter by being in upper half)
        final_pixels = []
        for c, r in pixels:
            if r < 14:  # eyes/brows region
                nc, nr = c + gaze_c, r + gaze_r
                if 0 <= nc < self.GRID_COLS and 0 <= nr < self.GRID_ROWS:
                    final_pixels.append((nc, nr))
            else:
                final_pixels.append((c, r))

        # Remove duplicates
        final_pixels = list(dict.fromkeys(final_pixels))

        # 5. Draw active LED pixels with glow
        for c, r in final_pixels:
            self._draw_led_pixel(c, r, color, glow=True)

        # 6. Subtle scanline effect (horizontal dim lines)
        for r in range(0, self.HEIGHT, 4):
            pygame.draw.line(screen, (0, 0, 0, 30), (0, r), (self.WIDTH, r), 1)


    def get_state(self) -> dict:
        with self.lock:
            return {
                "emotion": self._emotion,
                "running": self.running,
                "resolution": f"{self.WIDTH}x{self.HEIGHT}",
            }


# ============ Standalone Test ============
if __name__ == "__main__":
    display = CuteFaceDisplay()
    if display.init():
        emotions = ["neutral", "happy", "sad", "angry", "surprised", "sleepy", "love", "cool"]
        idx = 0
        try:
            while True:
                display.set_emotion(emotions[idx])
                idx = (idx + 1) % len(emotions)
                time.sleep(3)
        except KeyboardInterrupt:
            pass
        finally:
            display.stop()
    else:
        print("Display not available (no HDMI or no pygame).")
        print("  - If running on KDE Plasma, make sure DISPLAY=:1 is set")
        print("  - If running headless, connect HDMI and restart")
