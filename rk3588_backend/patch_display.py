import re

with open('/tmp/rk3588_car_project/rk3588_backend/display.py', 'r') as f:
    content = f.read()

# 1. Replace the SDL_VIDEODRIVER detection block at top
old_top = '''# Auto-detect display driver
# If DISPLAY is set, we're on a desktop (KDE/GNOME/X11) -> use x11
# Otherwise try kmsdrm for direct HDMI
if os.environ.get('DISPLAY'):
    os.environ['SDL_VIDEODRIVER'] = 'x11'
elif os.path.exists('/dev/dri/card0'):
    os.environ['SDL_VIDEODRIVER'] = 'kmsdrm'
# Fallbacks: 'fbcon' for pure framebuffer, 'dummy' for headless'''

new_top = '''# Auto-detect display driver
# If DISPLAY is set, we're on a desktop (KDE/GNOME/X11) -> use x11
# Otherwise try kmsdrm for direct HDMI
def _auto_detect_display():
    if os.environ.get('DISPLAY'):
        os.environ['SDL_VIDEODRIVER'] = 'x11'
        print(f"[FaceDisplay] DISPLAY={os.environ['DISPLAY']} detected, using x11")
        return
    # Try to auto-detect active X11 session (e.g., SSH start but KDE already running)
    for display_num in ['0', '1', '2']:
        if os.path.exists(f'/tmp/.X11-unix/X{display_num}'):
            os.environ['DISPLAY'] = f':{display_num}'
            os.environ['SDL_VIDEODRIVER'] = 'x11'
            print(f"[FaceDisplay] Auto-detected DISPLAY=:{display_num} from /tmp/.X11-unix/X{display_num}")
            return
    if os.path.exists('/dev/dri/card0'):
        os.environ['SDL_VIDEODRIVER'] = 'kmsdrm'
        print("[FaceDisplay] No X11 found, falling back to KMS/DRM")
    else:
        print("[FaceDisplay] No display driver available (no X11, no KMS/DRM)")

_auto_detect_display()
# Fallbacks: 'fbcon' for pure framebuffer, 'dummy' for headless'''

content = content.replace(old_top, new_top)

# 2. Rewrite init() method
old_init = '''    def init(self) -> bool:
        """Initialize pygame and enter fullscreen mode"""
        try:
            pygame.init()
            pygame.display.init()

            # Detect display mode
            is_x11 = os.environ.get('SDL_VIDEODRIVER') == 'x11'
            
            if is_x11:
                # On KDE Plasma / desktop: create borderless window at 800x480
                # Position at top-left of primary display
                os.environ['SDL_VIDEO_WINDOW_POS'] = '0,0'
                self.screen = pygame.display.set_mode(
                    (self.WIDTH, self.HEIGHT),
                    pygame.NOFRAME | pygame.DOUBLEBUF
                )
                print("[FaceDisplay] Running in X11 windowed mode (KDE Plasma)")
            else:
                # Try KMS/DRM first (best for RK3588S direct HDMI)
                try:
                    self.screen = pygame.display.set_mode(
                        (self.WIDTH, self.HEIGHT),
                        pygame.FULLSCREEN | pygame.DOUBLEBUF | pygame.HWSURFACE
                    )
                    print("[FaceDisplay] Running in KMS/DRM fullscreen mode")
                except Exception:
                    # Fallback to windowed if display driver fails
                    self.screen = pygame.display.set_mode((self.WIDTH, self.HEIGHT))
                    print("[FaceDisplay] Falling back to windowed mode")

            pygame.mouse.set_visible(False)
            self.running = True
            self.render_thread = threading.Thread(target=self._render_loop, daemon=True)
            self.render_thread.start()
            print(f"[FaceDisplay] Started {self.WIDTH}x{self.HEIGHT} cute face display")
            return True
        except Exception as e:
            print(f"[FaceDisplay] Failed to init: {e}")
            return False'''

new_init = '''    def init(self) -> bool:
        """Initialize pygame and enter fullscreen mode"""
        try:
            print("[FaceDisplay] pygame.init() starting...")
            pygame.init()
            pygame.display.init()
            print(f"[FaceDisplay] pygame display driver: {pygame.display.get_driver()}")

            # Detect display mode
            is_x11 = os.environ.get('SDL_VIDEODRIVER') == 'x11' or bool(os.environ.get('DISPLAY'))
            
            if is_x11:
                # On KDE Plasma / desktop: FULLSCREEN to cover entire display
                # This avoids the NOFRAME window being hidden by desktop compositor
                os.environ['SDL_VIDEO_WINDOW_POS'] = '0,0'
                os.environ['SDL_VIDEO_CENTERED'] = '0'
                print(f"[FaceDisplay] Creating X11 fullscreen window {self.WIDTH}x{self.HEIGHT}")
                self.screen = pygame.display.set_mode(
                    (self.WIDTH, self.HEIGHT),
                    pygame.FULLSCREEN | pygame.DOUBLEBUF
                )
                print("[FaceDisplay] X11 fullscreen surface created OK")
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
            return False'''

content = content.replace(old_init, new_init)

# 3. Wrap render loop in try/except + add fps logging
old_render_loop = '''    def _render_loop(self):
        """Main rendering loop running in background thread"""
        clock = pygame.time.Clock()
        while self.running:
            dt = clock.tick(self.FPS) / 1000.0
            self._time += dt
            self._update_animations(dt)
            self._draw_frame()
            pygame.display.flip()

            # Process quit events
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE or event.key == pygame.K_q:
                        self.running = False'''

new_render_loop = '''    def _render_loop(self):
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
                time.sleep(0.5)'''

content = content.replace(old_render_loop, new_render_loop)

with open('/tmp/rk3588_car_project/rk3588_backend/display.py', 'w') as f:
    f.write(content)

print("display.py patch applied successfully")
