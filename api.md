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

# HTTP API 文档

## 基本配置

- 基础 URL: `http://localhost:8000`
- 内容类型: `application/json`、`multipart/form-data`(文件上传)
- 认证方式: 无需认证(本地应用)

## 会话管理 API

### 切换会议

```
POST /api/switch_meeting
```

**请求参数:**

```
Content-Type: application/json

{
  "meeting_id": 整数
}
```

**响应:**

```json
{
  "success": true
}
```

### 分析对话

```
POST /api/analyze_dialogue
```

**请求体:**

```json
{
  "dialogue": "对话内容..."
}
```

**响应:**

```json
{
  "success": true,
  "analysis": {
    // 分析结果
  }
}
```

## 文档管理 API

### 上传文档

```
POST /api/documents/upload
```

**请求参数:**

```
Content-Type: multipart/form-data

file: 文件
doc_type: "legal" | "educational" | "article" | "other"
title: 文档标题 (可选)
description: 文档描述 (可选)
visibility: "public" | "private" (默认 "private")
meeting_id: 整数 (私有文档必填)
```

**响应:**

```json
{
  "success": true,
  "doc_id": "string",
  "file_info": {
    "original_filename": "string",
    "content_type": "string",
    "file_path": "string",
    "file_size": "number"
  }
}
```

### 获取文档处理状态

```
GET /api/documents/{doc_id}/status
```

**响应:**

```json
{
  "success": true,
  "status": "uploaded" | "processing" | "completed" | "error",
  "progress": "number(0-100)",
  "message": "状态描述"
}
```

### 获取文档结构预览

```
GET /api/documents/{doc_id}/preview
```

**响应:**

```json
{
  "success": true,
  "doc_id": "string",
  "title": "string",
  "doc_type": "string",
  "content_type": "string",
  "structure": {
    "hierarchy": [
      {
        "level": "number",
        "title": "string",
        "id": "string",
        "children": "number"
      }
    ],
    "total_chunks": "number",
    "sample_chunks": [
      {
        "id": "string",
        "text": "string",
        "hierarchy_path": ["string"]
      }
    ]
  }
}
```

### 获取文档列表

```
GET /api/documents
```

**查询参数:**

```
meeting_id: 会议ID (可选，用于获取特定会议的文档)
doc_type: 文档类型 (可选，多个用逗号分隔)
visibility: "public" | "private" | "all" (可选，默认 "all")
query: 搜索关键词 (可选)
page: 页码 (默认 1)
limit: 每页数量 (默认 20)
```

**响应:**

```json
{
  "success": true,
  "documents": [
    {
      "doc_id": "string",
      "title": "string",
      "doc_type": "string",
      "content_type": "string",
      "description": "string",
      "visibility": "public" | "private",
      "meeting_id": "number?",
      "created_at": "number",
      "updated_at": "number",
      "status": "string",
      "chunks_count": "number",
      "file_size": "number",
      "structure_summary": "string",
      "file_path": "string"
    }
  ],
  "total": "number",
  "page": "number",
  "limit": "number"
}
```

### 更新文档信息

```
PATCH /api/documents/{doc_id}
```

**请求体:**

```json
{
  "title": "string" (可选),
  "description": "string" (可选),
  "doc_type": "string" (可选),
  "visibility": "public" | "private" (可选),
  "meeting_id": "number" (visibility为private时必填)
}
```

**响应:**

```json
{
  "success": true,
  "doc_info": {
    // 更新后的文档信息
  }
}
```

### 删除文档

```
DELETE /api/documents/{doc_id}
```

**响应:**

```json
{
  "success": true
}
```

### 查询文档内容

```
POST /api/documents/query
```

**请求体:**

```json
{
  "query": "string",
  "meeting_id": "number" (可选，用于过滤私有文档),
  "filter": {
    "doc_ids": ["string"] (可选),
    "doc_types": ["string"] (可选),
    "visibility": "public" | "private" | "all" (可选，默认 "all")
  },
  "limit": "number" (可选，默认 5)
}
```

**响应:**

```json
{
  "success": true,
  "results": [
    {
      "chunk_id": "string",
      "text": "string",
      "doc_id": "string",
      "doc_title": "string",
      "visibility": "public" | "private",
      "score": "number(0-1)",
      "hierarchy": [
        {
          "level": "number",
          "title": "string",
          "id": "string"
        }
      ],
      "citation": "string"
    }
  ]
}
```

## 错误响应

所有 API 在出错时返回标准 HTTP 错误状态码，并提供详细信息：

```json
{
  "success": false,
  "error": "错误描述"
}
```

## 常见错误码

- 400: 请求参数错误
- 404: 资源未找到
- 429: 请求过于频繁
- 500: 服务器内部错误

### 文档相关错误码

- 3001: 文档上传失败
- 3002: 文档解析错误
- 3003: 文档查询错误
- 3004: 文档删除错误
