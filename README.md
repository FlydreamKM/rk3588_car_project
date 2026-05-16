# RK3588S 智能小车控制项目

手机 Flutter APP ← **WiFi** → RK3588S（Python Flask 后端）← **串口** → STM32 电机驱动器

---

## 项目结构

```
rk3588_car_project/
├── rk3588_backend/          # RK3588S Python 后端
│   ├── motor_driver.py      # JustFloat 帧解析 + FireWater 命令
│   ├── app.py               # Flask API + MJPEG 视频流 + SSE 遥测
│   ├── requirements.txt     # Python 依赖
│   └── start.sh             # 一键启动脚本
├── flutter_app/             # Flutter 手机 APP
│   ├── android/             # Android 配置
│   ├── lib/
│   │   ├── main.dart
│   │   ├── providers/robot_provider.dart
│   │   ├── services/api_service.dart
│   │   ├── screens/main_screen.dart
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
- [x] `app.py` — Flask 后端
  - MJPEG 视频流 `/video_feed`
  - RESTful API 控制 `/api/control`, `/api/motor/*`
  - SSE 实时遥测 `/api/telemetry`
  - 视频帧 HUD 叠加（电池、速度、十字准星）
- [x] 差速驱动速度映射 `set_car_speed(linear, angular)`

### Flutter 手机 APP
- [x] MJPEG 视频流显示（`mjpeg_stream` 包）
- [x] 仪表盘 UI（速度表、电池、电机状态）
- [x] 摇杆控制（`flutter_joystick`）
- [x] 模式切换按钮（手动/自动/跟随/手势/停车/语音）
- [x] 灯光控制（LED 颜色/模式）
- [x] 毛玻璃 UI 效果
- [x] 服务器 IP 设置

---

## APK 构建方式（三选一）

当前沙箱环境受限（无 Java/Android SDK），APK 需在外部环境构建。

### 方案一：GitHub Actions（推荐，全自动）

将本项目推送到 GitHub，自动构建 APK：

```bash
cd rk3588_car_project
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_NAME/rk3588_car.git
git push -u origin main
```

推送后 GitHub Actions 自动运行，APK 可在 **Actions → Artifacts** 中下载。

如需发布到 Release，在仓库设置中启用 `GITHUB_TOKEN` 权限即可。

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

脚本会自动安装 OpenJDK 17、Android SDK、Flutter SDK，然后构建 APK。

---

## RK3588S 部署

### 1. 安装依赖

```bash
cd rk3588_backend
sudo apt update
sudo apt install -y python3-pip python3-venv libopencv-dev
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 连接电机驱动器

STM32 电机驱动器通过 USB 转串口连接到 RK3588S：

```bash
ls /dev/ttyUSB*   # 确认串口设备
# 如果权限不足：
sudo usermod -aG dialout $USER
```

### 3. 启动后端

```bash
export MOTOR_PORT=/dev/ttyUSB0   # 默认，可按需修改
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

---

## 注意事项

1. **串口权限**：确保 RK3588S 用户对 `/dev/ttyUSB0` 有读写权限，加入 `dialout` 组。
2. **WiFi 同网段**：手机和 RK3588S 必须在同一 WiFi 网络下，APP 默认连接 `192.168.1.100`，可在设置中修改。
3. **电机换算**：`set_car_speed` 中的差速映射需要按实际车轮半径和轮距调整。
4. **摄像头**：后端自动检测 `/dev/video0`，如果 RK3588S 没有摄像头会显示离线画面。
5. **调试**：motor_driver.py 可以直接运行测试串口通信：`python motor_driver.py /dev/ttyUSB0`

---

## 依赖版本

- Flutter SDK >= 3.24.0
- Android SDK API 34
- OpenJDK 17
- Python 3.10+
- OpenCV 4.9+
- pyserial 3.5

---

## License

MIT
