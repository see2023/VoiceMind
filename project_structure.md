/
├── meeting_assistant/ # Flutter 项目
│ ├── lib/
│ │ ├── core/  
│ │ │ ├── audio/ # 音频处理
│ │ │ │ ├── audio_service.dart # 音频录制服务
│ │ │ │ ├── audio_player_service.dart # 音频播放服务（支持对话片段回放）
│ │ │ │ └── audio_converter.dart # 音频格式转换
│ │ │ ├── socket/ # Socket.IO 客户端
│ │ │ │ ├── socket_service.dart # WebSocket 通信（实时转写）
│ │ │ │ └── meeting_service.dart # 会议相关的 Socket 服务
│ │ │ ├── storage/ # Isar DB 存储
│ │ │ │ ├── models/ # 数据模型定义
│ │ │ │ │ ├── meeting.dart # 会议模型（标题、目标、笔记等）
│ │ │ │ │ ├── utterance.dart # 对话内容模型（文本、时间戳、说话人等）
│ │ │ │ │ ├── audio_chunk.dart # 音频片段模型（对应每条对话的音频）
│ │ │ │ │ ├── user.dart # 全局用户信息（用于说话人标记）
│ │ │ │ │ ├── meeting_participant.dart # 会议参与者（用户-派别关系）
│ │ │ │ │ ├── speaker.dart # 声音特征标记（说话人识别结果）
│ │ │ │ │ ├── stance.dart # 会议派别定义
│ │ │ │ │ ├── proposition.dart # 主张/论点
│ │ │ │ │ └── proposition_stance.dart # 用户对主张的态度
│ │ │ │ ├── services/ # 存储服务
│ │ │ │ │ └── isar_service.dart # Isar 数据库操作（支持分页加载对话）
│ │ │ ├── utils/ # 工具类
│ │ │ │ ├── logger.dart # 日志工具
│ │ │ │ └── speaker_utils.dart # 说话人工具（ID 解析等）
│ │ │ ├── analysis/ # 分析模块
│ │ ├── controllers/ # 控制器
│ │ │ ├── meeting_controller.dart # 会议管理（对话数据统一管理、分页加载）
│ │ │ └── recording_controller.dart # 录音控制（实时转写、音频处理）
│ │ ├── screens/ # 界面
│ │ │ ├── home_screen.dart # 主界面
│ │ │ ├── control_panel.dart # 控制面板（录音控制等）
│ │ │ └── conversation_panel.dart # 对话面板（显示、滚动加载、自动滚动）
│ │ ├── widgets/ # 可复用组件
│ │ │ ├── conversation_item.dart # 对话项组件（文本编辑、说话人修改等）
│ │ │ ├── editable_text_field.dart # 可编辑文本框
│ │ │ ├── meeting_info_dialog.dart # 会议信息对话框
│ │ │ └── analysis_settings_panel.dart # 分析设置面板
│ │ └── main.dart # 应用入口
│ ├── assets/ # 静态资源
│ └── pubspec.yaml # 项目配置
│
├── python_backend/ # Python 后端
│ ├── config/
│ ├── core/
│ ├── service/
│ │ ├── audio_processor.py # 音频处理主模块
│ │ ├── voice_detector.py # VAD 检测模块
│ │ ├── ring_buffer.py # 音频缓冲区
│ │ ├── sense_voice.py # 语音识别模块
│ │ ├── speaker.py # 说话人识别模块
│ │ └── socket_service.py # WebSocket 服务
│ ├── tools/
│ │ └── bin_tools.py # 二进制工具函数
│ └── requirements.txt
│ ├── main.py
│
├── scripts/ # 构建脚本
│ ├── build_windows.ps1 # Windows 打包脚本
│ ├── build_macos.sh # macOS 打包脚本
│ └── pack_python_env.py # Python 环境打包脚本
│
└── README.md
