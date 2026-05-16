# RK3588S 智能小车控制项目

手机 Flutter APP ← **WiFi** → RK3588S（Python Flask 后端）← **串口** → STM32 电机驱动器

---

## 项目结构

```
rk3588_car_project/
├── rk3588_backend/          # RK3588S Python 后端
│   ├── motor_driver.py      # JustFloat 帧解析 + FireWater 命令
│   ├── servo_driver.py      # PWM 舵机转向控制
│   ├── imu_driver.py        # IMU 姿态传感器读取 (UART)
│   ├── tracking_driver.py   # 8路红外巡线模块 (UART)
│   ├── PID.py               # PID 控制器
│   ├── display.py           # 800x480 HDMI 可爱表情显示
│   ├── app.py               # Flask API + MJPEG 视频流 + SSE 遥测
│   ├── requirements.txt     # Python 依赖
│   └── start.sh             # 一键启动脚本
├── flutter_app/             # Flutter 手机 APP
│   ├── android/             # Android 配置
│   ├── lib/
│   │   ├── main.dart
│   │   ├── providers/robot_provider.dart
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   └── ssh_service.dart    # SSH 远程连接
│   │   ├── screens/
│   │   │   ├── connection_screen.dart  # 连接页面 + 一键启动
│   │   │   └── main_screen.dart
│   │   └── widgets/         # 视频流、仪表盘、摇杆、灯光等
│   └── pubspec.yaml         # Flutter 依赖
├── .github/workflows/
│   └── build.yml            # GitHub Actions 自动构建 APK
├── Dockerfile               # Docker 构建 APK
├── build_apk.sh             # 本地构建脚本
├── setup_and_build.sh       # 完整环境安装 + 构建脚本
└── README.md                # 本文件
```

---

## 已完成内容

### RK3588S 后端
- [x] `motor_driver.py` — VOFA-only 模式电机驱动
  - JustFloat 帧解析（10 通道 float32，帧尾 `0x00 0x00 0x80 0x7f`）
  - FireWater 文本命令发送（M/P/C/V/S）
  - 串口自动重连、多线程读写分离
- [x] `servo_driver.py` — PWM 舵机转向控制
  - 基于 Linux sysfs PWM 接口
  - SERVO_MID_DUTY=157000ns, SERVO_R_LIMIT_DUTY=15500ns, SERVO_L_LIMIT_DUTY=13500ns
  - 角度百分比映射：-100%（左极限）~ 0%（中位）~ +100%（右极限）
- [x] `imu_driver.py` — YB-IMU 姿态传感器
  - 通过 UART/USB-to-TTL 连接
  - 输出：加速度计、陀螺仪、磁力计、四元数、欧拉角、气压计、温度
  - 自动端口探测：/dev/myimu, /dev/ttyUSB*, /dev/ttyACM*
- [x] `tracking_driver.py` — 8路红外巡线模块
  - 通过 UART/USB-to-TTL 连接，协议 "$0,0,1,0,1,1,1,0#"
  - 内置位置式 PID 控制器
  - 自动巡线模式：差分转向闭环控制
- [x] `PID.py` — 位置式/增量式 PID 控制器
- [x] `display.py` — 800x480 HDMI 全屏可爱表情显示
  - 基于 pygame + KMS/DRM 直连（无需 X11）
  - 8 种表情：neutral, happy, sad, angry, surprised, sleepy, love, cool
  - 自动眨眼动画、腮红、眼镜、爱心眼等装饰
  - 情绪与运行模式联动
- [x] `app.py` — Flask 后端
  - MJPEG 视频流 `/video_feed`
  - RESTful API 控制 `/api/control`, `/api/motor/*`, `/api/servo`, `/api/imu`, `/api/tracking`, `/api/display/*`
  - SSE 实时遥测 `/api/telemetry`
  - 视频帧 HUD 叠加（电池、速度、航向、巡线状态、十字准星）
  - SSH 一键启动 `/api/ssh/start`
- [x] 差速驱动速度映射 `set_car_speed(linear, angular)`

### Flutter 手机 APP
- [x] **连接页面** — 首次启动即进入连接配置
  - RK3588S IP 地址输入
  - SSH 用户名/密码/端口配置（可选）
  - HTTP API 连接测试
  - SSH 连接测试
  - **一键启动服务端** — 通过 API 或 SSH 远程启动后端
- [x] SSH 终端连接（`dartssh2`）
  - 纯 Dart SSH 客户端，无需 Native 代码
  - 支持远程执行命令、启动服务端脚本
- [x] MJPEG 视频流显示（`mjpeg_stream` 包）
- [x] 仪表盘 UI（速度表、电池、电机状态、航向角）
- [x] 摇杆控制（`flutter_joystick`）
- [x] 模式切换按钮（手动/自动/跟随/巡线/泊车/手势/语音）
- [x] **舵机转向滑块** — 实时控制 + 回中按钮
- [x] **8路巡线可视化** — 8个传感器实时状态 + 开始/停止巡线按钮
- [x] **表情显示控制** — 8种可爱表情一键切换
- [x] 灯光控制（LED 颜色/模式）
- [x] 毛玻璃 UI 效果
- [x] 服务器 IP 设置 + 返回连接页面

---

## APK 构建方式（三选一）

### 方案一：GitHub Actions（推荐，全自动）

将本项目推送到 GitHub，自动构建 APK：

```bash
cd rk3588_car_project
git add .
git commit -m "Update: servo, IMU, tracking, display, SSH, connection screen"
git push origin main
```

推送后 GitHub Actions 自动运行，APK 可在 **Actions → Artifacts** 中下载。

### 方案二：Docker 构建

```bash
cd rk3588_car_project
docker build -t smart-car-builder .
docker run --rm -v $(pwd):/project smart-car-builder
# APK 输出在 flutter_app/build/app/outputs/flutter-apk/
```

### 方案三：本地 Ubuntu 构建

```bash
cd rk3588_car_project
chmod +x setup_and_build.sh
./setup_and_build.sh
```

---

## RK3588S 部署

### 1. 安装依赖

```bash
cd rk3588_backend
sudo apt update
sudo apt install -y python3-pip python3-venv libopencv-dev libsdl2-dev
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 连接硬件

| 设备 | 连接方式 | 默认端口 | 环境变量 |
|------|----------|----------|----------|
| STM32 电机驱动器 | USB 转串口 | `/dev/ttyUSB0` | `MOTOR_PORT` |
| IMU 姿态传感器 | USB 转 TTL | 自动探测 | — |
| 8路巡线模块 | USB 转 TTL | `/dev/ttyUSB1` | `TRACKING_PORT` |
| 舵机 PWM | PWM sysfs | `pwmchip0/pwm0` | — |
| HDMI 显示屏 | HDMI | 800x480 | — |

检查串口设备：
```bash
ls /dev/ttyUSB* /dev/ttyACM*
sudo usermod -aG dialout $USER  # 加入 dialout 组获取串口权限
```

### 3. 启动后端

```bash
export MOTOR_PORT=/dev/ttyUSB0
export TRACKING_PORT=/dev/ttyUSB1
./start.sh
```

后端启动后：
- API 地址：`http://RK3588S_IP:5000`
- 视频流：`http://RK3588S_IP:5000/video_feed`
- 实时数据：`http://RK3588S_IP:5000/api/telemetry`（SSE）

### 4. 防火墙

```bash
sudo ufw allow 5000/tcp
# 或 iptables
sudo iptables -I INPUT -p tcp --dport 5000 -j ACCEPT
```

---

## 通信协议

### JustFloat 帧格式（STM32 → RK3588S）

| 字节 | 内容 |
|------|------|
| 0-3  | ch0: motor1 实际速度 (rad/s) |
| 4-7  | ch1: motor1 实际角度 (rad) |
| 8-11 | ch2: motor1 PWM |
| ...  | ... |
| 36-39| ch9: motor2 目标角度 (rad) |
| 40-43| 帧尾: `0x00 0x00 0x80 0x7f` |

### FireWater 命令（RK3588S → STM32）

| 命令 | 格式 | 说明 |
|------|------|------|
| M | `M <motor> <mode> <speed> <angle> <accel> <decel>` | 设置目标参数 |
| P | `P <motor> <pid_type> <kp> <ki> <kd>` | 设置 PID |
| C | `C <motor> <code>` | 控制指令（0=ENABLE, 1=DISABLE, 2=HOME, 3=EMERGENCY, 4=CLEAR_FAULT） |
| V | `V <interval_ms>` | 输出频率（5=200Hz） |
| S | `S` | 状态查询 |

### 8路巡线协议

模块通过 UART 发送 ASCII 帧：
```
$<s1>,<s2>,<s3>,<s4>,<s5>,<s6>,<s7>,<s8>#
```
其中 `s1~s8` 为 0 或 1（0 = 检测到黑线，1 = 未检测到）

---

## API 端点速查

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/video_feed` | MJPEG 视频流 |
| GET | `/api/status` | 完整状态 |
| POST | `/api/control` | 运动控制 |
| POST | `/api/mode` | 模式切换 |
| POST | `/api/servo` | 舵机角度（-100 ~ +100） |
| POST | `/api/servo/center` | 舵机回中 |
| GET | `/api/imu` | IMU 数据 |
| GET | `/api/tracking` | 巡线数据 |
| POST | `/api/tracking/start` | 启动自动巡线 |
| POST | `/api/tracking/stop` | 停止巡线 |
| POST | `/api/display/emotion` | 设置表情 |
| POST | `/api/ssh/start` | 一键启动服务端 |
| GET | `/api/ssh/status` | 服务端状态 |
| POST | `/api/ssh/stop` | 停止服务端 |
| GET | `/api/telemetry` | SSE 实时推送 |

---

## 注意事项

1. **串口权限**：确保 RK3588S 用户对 `/dev/ttyUSB*` 有读写权限，加入 `dialout` 组。
2. **PWM 设备树**：舵机 PWM 需要在内核设备树中启用对应 PWM 通道。
3. **HDMI 显示**：`display.py` 使用 KMS/DRM 直连，确保 SDL2 支持 DRM 后端。如无显示，可尝试在 X11 桌面环境下运行（自动回退到窗口模式）。
4. **IMU 波特率**：默认 115200，如使用其他型号请修改 `imu_driver.py` 中的 `baudrate`。
5. **WiFi 同网段**：手机和 RK3588S 必须在同一 WiFi 网络下。
6. **电机换算**：`set_car_speed` 中的差速映射需要按实际车轮半径和轮距调整。
7. **摄像头**：后端自动检测 `/dev/video0`，如果 RK3588S 没有摄像头会显示离线画面。
8. **调试**：各 driver 模块均可直接运行测试：`python servo_driver.py`, `python imu_driver.py`, `python tracking_driver.py`, `python display.py`。

---

## 依赖版本

- Flutter SDK >= 3.24.0
- Android SDK API 34
- OpenJDK 17
- Python 3.10+
- OpenCV 4.9+
- pyserial 3.5
- pygame 2.6.0
- paramiko 3.4.0

---

## License

MIT
