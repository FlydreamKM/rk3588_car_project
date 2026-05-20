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
from typing import Optional

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
    if os.environ.get('SDL_VIDEODRIVER') == 'x11':
        # Bypass KWin compositor to avoid GL context conflict with Mali GPU
        os.environ['SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR'] = '1'
        print("[FaceDisplay] Set NET_WM_BYPASS_COMPOSITOR=1 to avoid KWin GL conflict")
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
    800x480 HDMI cute face display.
    Fullscreen animated robot face with blinking and emotion transitions.
    """

    WIDTH = 800
    HEIGHT = 480
    FPS = 30

    # Colors
    BG_COLOR = (255, 240, 245)       # Soft pink-white background
    FACE_COLOR = (255, 228, 196)     # Bisque face
    EYE_WHITE = (255, 255, 255)
    EYE_PUPIL = (50, 50, 50)
    CHEEK_COLOR = (255, 182, 193)    # Light pink
    MOUTH_COLOR = (200, 80, 80)
    ACCENT_COLOR = (100, 149, 237)   # Cornflower blue

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
        self._next_blink = 2.5 + (hash(id(self)) % 100) / 50.0  # randomize slightly
        self._time = 0.0

        # Eye tracking target (normalized -1 to 1)
        self._eye_target_x = 0.0
        self._eye_target_y = 0.0

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
                # On KDE Plasma / desktop: pure software surface, bypass compositor
                # NOFRAME only (no FULLSCREEN/DOUBLEBUF/HWSURFACE) to avoid Mali GL conflict with KWin
                os.environ['SDL_VIDEO_WINDOW_POS'] = '0,0'
                os.environ['SDL_VIDEO_CENTERED'] = '0'
                print(f"[FaceDisplay] Creating X11 NOFRAME window {self.WIDTH}x{self.HEIGHT} (software render)")
                self.screen = pygame.display.set_mode(
                    (self.WIDTH, self.HEIGHT),
                    pygame.NOFRAME
                )
                print("[FaceDisplay] X11 software surface created OK")
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

            pygame.mouse.set_visible(False)
            self.running = True
            self.render_thread = threading.Thread(target=self._render_loop, daemon=True)
            self.render_thread.start()
            print(f"[FaceDisplay] Started {self.WIDTH}x{self.HEIGHT} cute face display")
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
                pygame.display.flip()
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

    def _lerp(self, a: float, b: float, t: float) -> float:
        return a + (b - a) * t

    def _draw_frame(self):
        """Draw the complete cute face frame"""
        if not self.screen:
            return

        screen = self.screen
        w, h = self.WIDTH, self.HEIGHT
        cx, cy = w // 2, h // 2
        emotion = self._emotion
        t = self._emotion_transition

        # Background
        screen.fill(self.BG_COLOR)

        # Decorative rounded background card
        card_rect = pygame.Rect(40, 20, w - 80, h - 40)
        pygame.draw.rect(screen, (255, 255, 255), card_rect, border_radius=30)
        pygame.draw.rect(screen, self.ACCENT_COLOR, card_rect, width=4, border_radius=30)

        # Face base (round shape with subtle shadow)
        face_radius = 160
        face_center = (cx, cy - 10)
        shadow_offset = (8, 12)
        pygame.draw.circle(screen, (200, 200, 210),
                          (face_center[0] + shadow_offset[0], face_center[1] + shadow_offset[1]), face_radius)
        pygame.draw.circle(screen, self.FACE_COLOR, face_center, face_radius)

        # Determine eye/mouth parameters by emotion
        eye_open_h = 50
        eye_open_w = 55
        eye_y_offset = -40
        mouth_w = 60
        mouth_h = 20
        mouth_y = 50
        blush_alpha = 180
        brow_angle = 0
        extra_features = []

        if emotion == "happy":
            eye_open_h = 35  # ^_^ style
            mouth_w = 80
            mouth_h = 40
            blush_alpha = 220
        elif emotion == "sad":
            eye_y_offset = -30
            brow_angle = -15
            mouth_h = -15
            mouth_w = 50
        elif emotion == "angry":
            eye_open_h = 45
            brow_angle = 20
            mouth_h = -25
            mouth_w = 40
        elif emotion == "surprised":
            eye_open_h = 70
            eye_open_w = 50
            mouth_w = 30
            mouth_h = 40
        elif emotion == "sleepy":
            eye_open_h = 8
            mouth_w = 30
            mouth_h = 5
            blush_alpha = 120
        elif emotion == "love":
            eye_open_h = 40
            eye_open_w = 50
            blush_alpha = 255
            extra_features = ["heart_eyes"]
        elif emotion == "cool":
            eye_open_h = 30
            blush_alpha = 0
            extra_features = ["sunglasses"]

        # Apply blink (interpolate toward closed)
        blink = self._blink_state
        eye_h = self._lerp(eye_open_h, 2, blink)
        eye_w = eye_open_w

        # Eye positions with slight gaze tracking
        gaze_x = self._eye_target_x * 8
        gaze_y = self._eye_target_y * 6

        left_eye_center = (cx - 70 + gaze_x, cy + eye_y_offset + gaze_y)
        right_eye_center = (cx + 70 + gaze_x, cy + eye_y_offset + gaze_y)

        # Draw eyes
        if "heart_eyes" in extra_features:
            self._draw_heart_eye(screen, left_eye_center, eye_w, eye_h)
            self._draw_heart_eye(screen, right_eye_center, eye_w, eye_h)
        elif "sunglasses" in extra_features:
            self._draw_sunglasses(screen, left_eye_center, right_eye_center, eye_w + 10)
        else:
            self._draw_eye(screen, left_eye_center, eye_w, eye_h)
            self._draw_eye(screen, right_eye_center, eye_w, eye_h)

        # Eyebrows (for angry/sad)
        if brow_angle != 0:
            brow_len = 40
            brow_y = eye_y_offset - 50
            # Left brow
            self._draw_brow(screen, (cx - 70, cy + brow_y), brow_len, -brow_angle)
            # Right brow
            self._draw_brow(screen, (cx + 70, cy + brow_y), brow_len, brow_angle)

        # Blush circles
        if blush_alpha > 0:
            blush_surf = pygame.Surface((80, 50), pygame.SRCALPHA)
            pygame.draw.ellipse(blush_surf, (*self.CHEEK_COLOR, blush_alpha), (0, 0, 80, 50))
            screen.blit(blush_surf, (cx - 150, cy + 10))
            screen.blit(blush_surf, (cx + 70, cy + 10))

        # Mouth
        self._draw_mouth(screen, (cx, cy + mouth_y), mouth_w, mouth_h)

        # Decorative accessories
        if emotion == "cool":
            # Little "cool" sparkles
            sparkle_time = self._time * 2
            for i, offset in enumerate([(80, -120), (-90, -110), (0, -150)]):
                sx = cx + offset[0] + math.sin(sparkle_time + i * 1.5) * 5
                sy = cy + offset[1] + math.cos(sparkle_time + i * 1.2) * 5
                self._draw_sparkle(screen, (sx, sy), 12, (255, 215, 0))

        # Status text at bottom
        font = pygame.font.SysFont("notosanscjksc", 28) if pygame.font.get_default_font() else None
        if font:
            label = f"Mode: {emotion.upper()}"
            text_surf = font.render(label, True, (100, 100, 120))
            screen.blit(text_surf, (cx - text_surf.get_width() // 2, h - 60))

    def _draw_eye(self, screen, center, w, h):
        """Draw a single cute eye (white oval + pupil)"""
        # White sclera
        eye_rect = pygame.Rect(center[0] - w // 2, center[1] - h // 2, w, h)
        pygame.draw.ellipse(screen, self.EYE_WHITE, eye_rect)
        pygame.draw.ellipse(screen, (200, 200, 200), eye_rect, width=2)

        # Pupil (small circle near bottom for cute look)
        if h > 10:
            pupil_y = center[1] + h * 0.15
            pygame.draw.circle(screen, self.EYE_PUPIL, (center[0], int(pupil_y)), max(4, w // 5))
            # Highlight
            pygame.draw.circle(screen, (255, 255, 255), (center[0] - 3, int(pupil_y) - 3), 3)

    def _draw_heart_eye(self, screen, center, w, h):
        """Draw heart-shaped eye"""
        color = (255, 100, 150)
        scale = h / 40.0
        points = []
        for i in range(20):
            t = i / 20.0 * 2 * math.pi
            x = scale * 16 * (math.sin(t) ** 3)
            y = -scale * (13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
            points.append((center[0] + x, center[1] + y - 5))
        pygame.draw.polygon(screen, color, points)
        pygame.draw.polygon(screen, (200, 60, 100), points, width=2)

    def _draw_sunglasses(self, screen, left_eye, right_eye, size):
        """Draw sunglasses (cool mode)"""
        glass_color = (30, 30, 30)
        # Left lens
        pygame.draw.ellipse(screen, glass_color,
                            (left_eye[0] - size // 2, left_eye[1] - size // 3, size, size // 1.5))
        # Right lens
        pygame.draw.ellipse(screen, glass_color,
                            (right_eye[0] - size // 2, right_eye[1] - size // 3, size, size // 1.5))
        # Bridge
        pygame.draw.line(screen, glass_color,
                         (left_eye[0] + size // 2, left_eye[1]),
                         (right_eye[0] - size // 2, right_eye[1]), 4)
        # Reflection line
        pygame.draw.line(screen, (200, 200, 200),
                         (left_eye[0] - size // 3, left_eye[1] - size // 6),
                         (left_eye[0] + size // 4, left_eye[1] - size // 4), 2)

    def _draw_brow(self, screen, center, length, angle_deg):
        """Draw an eyebrow at angle"""
        angle = math.radians(angle_deg)
        dx = length * math.cos(angle) / 2
        dy = length * math.sin(angle) / 2
        start = (center[0] - dx, center[1] - dy)
        end = (center[0] + dx, center[1] + dy)
        pygame.draw.line(screen, (80, 50, 40), start, end, 5)
        pygame.draw.line(screen, (120, 80, 60), start, end, 3)

    def _draw_mouth(self, screen, center, w, h):
        """Draw mouth: positive h = smile (arc down), negative h = frown (arc up)"""
        if abs(h) < 3:
            # Small line mouth
            pygame.draw.line(screen, self.MOUTH_COLOR,
                             (center[0] - w // 2, center[1]),
                             (center[0] + w // 2, center[1]), 4)
        else:
            # Arc mouth
            rect = pygame.Rect(center[0] - w // 2, center[1] - abs(h), w, abs(h) * 2)
            if h > 0:
                # Smile: draw lower arc
                pygame.draw.arc(screen, self.MOUTH_COLOR, rect, math.pi, 2 * math.pi, 4)
            else:
                # Frown: draw upper arc
                pygame.draw.arc(screen, self.MOUTH_COLOR, rect, 0, math.pi, 4)
            # Fill for deeper smile
            if h > 15:
                inner_rect = pygame.Rect(center[0] - w // 2 + 8, center[1] - abs(h) + 8,
                                         w - 16, abs(h) * 2 - 16)
                pygame.draw.arc(screen, (255, 160, 160), inner_rect, math.pi, 2 * math.pi, 3)

    def _draw_sparkle(self, screen, center, size, color):
        """Draw a 4-point sparkle/star"""
        points = []
        for i in range(8):
            angle = i * math.pi / 4
            r = size if i % 2 == 0 else size * 0.4
            points.append((center[0] + r * math.cos(angle), center[1] + r * math.sin(angle)))
        pygame.draw.polygon(screen, color, points)
        pygame.draw.polygon(screen, (255, 255, 255), points, width=1)

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
        emotions = ["neutral", "happy", "love", "surprised", "cool", "sleepy", "sad", "angry"]
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
