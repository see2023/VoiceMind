# Socket.IO API 文档

## 连接设置

- URL: `http://localhost:8000`
- 传输协议: WebSocket
- 命名空间: `/`

## 事件定义

### 音频相关

#### `audio_stream` (Client -> Server)

发送音频流数据

> 音频要求：
>
> - 格式：PCM (16-bit)
> - 采样率：16000Hz
> - 通道数：单通道
> - 每次发送建议长度：100ms

```typescript
{
  audio: ArrayBuffer; // PCM音频数据 (16-bit, 单声道, 16kHz)
  timestamp: number; // 时间戳（秒）
}
```

#### `audio_stream_stop` (Client -> Server)

通知服务器音频流结束

> 说明：
>
> - 客户端主动停止录音时发送
> - 服务器收到后会停止相关的音频处理
> - 不需要携带任何数据

#### `transcription` (Server -> Client)

实时语音转写结果

> 说明：
>
> - 快速转写：基于短时语音片段的实时识别结果
> - 最终结果：基于完整语音片段的精确识别结果
> - 所有字段在两种结果中都可能存在，但最终结果的准确度更高

```typescript
{
  text: string;         // 转写文本
  speaker_id?: string;  // 说话人ID
  start_time: number;   // 开始时间
  end_time: number;     // 结束时间
  isFinal: boolean;     // 是否为最终结果
  timestamp: [[number, number]];    // 每个字的起止时间戳，音频开始为0，毫秒整数表示偏移
}
```

### 分析相关

#### `analysis_request` (Client -> Server)

请求分析特定内容

```typescript
{
  type: "stance" | "summary" | "suggestion";  // 分析类型
  content: {
    text: string;       // 待分析文本
    context?: {         // 上下文信息
      speakers: string[];    // 相关发言人
      background?: string;   // 背景信息
      topics?: string[];     // 相关主题
    }
  }
}
```

#### `analysis_result` (Server -> Client)

返回分析结果

```typescript
{
  type: "stance" | "summary" | "suggestion";  // 分析类型
  result: {
    content: string;    // 分析结果
    metadata: {
      confidence: number;    // 置信度
      references?: string[]; // 引用来源
      timestamp: number;     // 分析时间戳
    }
  }
}
```

### 系统状态

#### `system_status` (Server -> Client)

系统状态更新

```typescript
{
  status: "ready" | "processing" | "error";
  components: {
    audio: boolean;     // 音频系统状态
    llm: boolean;       // LLM系统状态
    rag: boolean;       // RAG系统状态
  }
  message?: string;     // 状态说明
}
```

#### `error` (双向)

错误信息

```typescript
{
  code: number;         // 错误代码
  message: string;      // 错误描述
  context?: any;        // 错误上下文
}
```

#### `speaker_detected` (Server -> Client)

```typescript
{
  speaker_id: string; // 说话人ID
  timestamp: number; // 检测时间戳（秒）
}
```

## 使用流程

1. **会议初始化**

   - 客户端连接 Socket.IO
   - 服务端发送 `system_status`
   - 客户端等待系统就绪

2. **音频处理**

   - 客户端持续发送 `audio_stream`
   - 服务端返回 `transcription`
   - 错误时发送 `error`

3. **实时分析**
   - 客户端发送 `analysis_request`
   - 服务端处理后返回 `analysis_result`
   - 服务端可主动推送新的分析结果

## 音频格式说明

### 1. 前端音频采集

- 格式：int16
- 采样率：16000Hz
- 通道：单通道
- 传输：WebSocket 二进制数据

### 2. 后端模型要求

#### VAD (Silero-VAD)

- 格式：float32
- 范围：[-1, 1]
- 采样率：16000Hz
- 通道：单通道

#### ASR (SenseVoice)

- 格式：int16
- 范围：[-32768, 32767]
- 采样率：16000Hz
- 通道：单通道
- 传入方式：rtc.AudioFrame

#### 说话人识别 (WeSpeaker)

- 格式：float32
- 范围：[-1, 1]
- 采样率：16000Hz
- 通道：单通道

## 数据持久化

### Python 端 Redis 存储

#### 声纹数据

```typescript
{
  "embedding:{speaker_id}": {
    embedding: number[],    // 声纹特征向量
    created_at: number,    // 首次识别时间
    updated_at: number,    // 最后更新时间
    samples_count: number, // 样本数量
    total_duration: number // 总时长(毫秒)
  }
}
```

## 错误代码

- 1000: 系统错误
- 1001: 音频处理错误
- 1002: 转写错误
- 1003: 分析错误
- 1004: 连接错误
- 1005: 格式错误
- 2001: 声纹提取错误
- 2002: 说话人识别错误
- 2003: 用户关联错误
