# FlashASR ASR 工作流详解

本文档详细介绍 FlashASR 的两套阿里云 Dashscope ASR 工作流，这是支撑整个业务的核心基础设施。

---

## 目录

1. [概述](#概述)
2. [实时流式 ASR (Realtime Mode)](#实时流式-asr-realtime-mode)
3. [文件闪传 ASR (File Flash Mode)](#文件闪传-asr-file-flash-mode)
4. [音频采集系统](#音频采集系统)
5. [双模式对比](#双模式对比)
6. [错误处理与容错](#错误处理与容错)

---

## 概述

FlashASR 采用双模式架构，根据用户场景选择最优的 ASR 方案：

```
┌─────────────────────────────────────────────────────────────────┐
│                         FlashASR ASR 架构                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────┐        ┌──────────────────────┐      │
│  │   实时流式模式         │        │   文件闪传模式         │      │
│  │  (Realtime Mode)     │        │  (File Flash Mode)   │      │
│  ├──────────────────────┤        ├──────────────────────┤      │
│  │ 协议: WebSocket      │        │ 协议: HTTP POST       │      │
│  │ 模型: qwen3-asr-flash│        │ 模型: qwen3-asr-flash │      │
│  │   -realtime          │        │                       │      │
│  │ 延迟: < 100ms        │        │ 延迟: 1-5s            │      │
│  │ 场景: 即时对话        │        │ 场景: 会议/长篇        │      │
│  └──────────────────────┘        └──────────────────────┘      │
│            │                               │                     │
│            └───────────────┬───────────────┘                     │
│                            ▼                                     │
│                  ┌─────────────────┐                             │
│                  │  音频采集系统     │                             │
│                  │ (AudioCapture)  │                             │
│                  │ 16kHz/16bit/单声道│                             │
│                  └─────────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 实时流式 ASR (Realtime Mode)

### 设计目标

- **超低延迟**: 从说话到文字出现 < 100ms
- **流式输出**: 边说边转，实时反馈
- **自动停检**: 检测到静音后自动停止
- **修正友好**: 支持前序词的动态修正

### 工作流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         实时流式 ASR 完整流程                                 │
└─────────────────────────────────────────────────────────────────────────────┘

  用户按下 ⌥+Space
        │
        ▼
┌───────────────────┐
│ 1. 建立 WebSocket  │  wss://dashscope.aliyuncs.com/api-ws/v1/realtime
│    连接            │  Authorization: Bearer {apiKey}
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 2. 发送会话配置     │  {
│    (Session Update)│    "type": "session.update",
└─────────┬─────────┘    "session": {
          │                "input_audio_format": "pcm",
          │                "sample_rate": 16000,
          │                "input_audio_transcription": {
          │                  "language": "zh"
          │                },
          │                "turn_detection": {
          │                  "type": "server_vad",
          │                  "threshold": 0.0,
          │                  "silence_duration_ms": 400
          │                }
          │              }
          │            }
          ▼
┌───────────────────┐
│ 3. 开始音频采集     │  AVAudioEngine → 16kHz PCM
└─────────┬─────────┘
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│ 4. 持续发送音频帧 (每 20ms)                                     │
│                                                                │
│  {                                                              │
│    "event_id": "event_1234567890_1234",                        │
│    "type": "input_audio_buffer.append",                        │
│    "audio": "base64编码的PCM数据"                              │
│  }                                                              │
│                                                                │
│  • 帧大小: 640 字节 (20ms × 16kHz × 2字节)                     │
│  • 编码: Base64                                                │
│  • 静音帧自动丢弃 (可选)                                        │
└───────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│ 5. 接收服务器事件流                                            │
│                                                                │
│  事件类型                │ 说明                                │
│  ───────────────────────┼───────────────────────────────────  │
│  session.created        │ 会话创建成功                          │
│  input_audio_buffer.    │ 检测到语音开始                        │
│  speech_started         │                                      │
│  input_audio_buffer.    │ 检测到语音结束                        │
│  speech_stopped         │                                      │
│  conversation.item.     │ 中间转写结果 (不稳定)                 │
│  input_audio_transcription.text                                │
│  conversation.item.     │ 最终转写结果 (稳定)                    │
│  input_audio_transcription.completed                           │
│  session.finished       │ 会话结束                              │
└───────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────┐
│ 6. 文本缓冲与合并   │  TranscriptBuffer 合并 stable + unstable
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 7. LCP 模拟输入     │  RealtimeTyper 计算差异并智能回退/输入
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 8. 用户停止或      │  用户手动停止 或 服务端 VAD 检测到静音
│    自动停止        │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 9. 发送结束指令     │  { "type": "session.finish" }
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 10. 等待最终结果    │  2秒超时保护
└─────────┬─────────┘
          │
          ▼
    完成转写，复制到剪贴板
```

### 核心代码: ASRWebSocketClient

```swift
// 文件: Sources/ASRWebSocketClient.swift

// WebSocket 连接建立
func connect() {
    var request = URLRequest(url: wsURL)
    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

    let wsTask = session.webSocketTask(with: request)
    wsTask.resume()
    receiveLoop()
}

// 发送音频帧
func sendAudioFrame(_ frame: Data) {
    let payload: [String: Any] = [
        "event_id": eventID(),
        "type": "input_audio_buffer.append",
        "audio": frame.base64EncodedString()
    ]
    sendJSON(payload)
}

// 会话配置
private func sendSessionUpdateIfNeeded() {
    let payload: [String: Any] = [
        "type": "session.update",
        "session": [
            "input_audio_format": "pcm",
            "sample_rate": 16000,
            "input_audio_transcription": ["language": language],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.0,
                "silence_duration_ms": 400
            ]
        ]
    ]
    sendJSON(payload)
}
```

### 事件处理机制

```swift
// 处理服务器返回的事件
private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    let obj = parseJSON(message)
    let type = obj["type"] as? String

    switch type {
    case "input_audio_buffer.speech_started":
        dispatch(.speechStarted)  // 取消自动停止倒计时

    case "input_audio_buffer.speech_stopped":
        dispatch(.speechStopped)  // 启动自动停止倒计时

    case "conversation.item.input_audio_transcription.text":
        // 部分结果: stable + stash 合并
        let stable = obj["text"] ?? ""
        let stash = obj["stash"] ?? ""
        dispatch(.partial(stable + stash))

    case "conversation.item.input_audio_transcription.completed":
        // 最终确定的结果
        dispatch(.final(obj["transcript"] ?? ""))
    }
}
```

---

## 文件闪传 ASR (File Flash Mode)

> v6.6 更新：文件录音链路已升级为“录音中滚动分段转写”，固定 `180s` 分段 + `10s` 重叠拼接。  
> 每个分段在录音过程中即落盘并转写，结果持续 checkpoint；录音末端异常不会导致已完成分段结果丢失。

### 设计目标

- **高质量**: 全量音频分析，转写精度更高
- **长时间**: 覆盖普通/Markdown/课堂录音上限（最长 3 小时）
- **流式响应**: 边转写边输出，减少等待感
- **失败重试**: 失败分段可单独重试，不阻塞可用结果输出
- **自动恢复**: 强退/崩溃后可自动恢复未完成分段

### 工作流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         文件闪传 ASR 完整流程                                 │
└─────────────────────────────────────────────────────────────────────────────┘

  用户按下 ⌥+←
        │
        ▼
┌───────────────────┐
│ 1. 开始音频采集     │  直接采集到内存 (不发送)
└─────────┬─────────┘
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│ 2. 持续采集音频 (最长 5 分钟)                                   │
│                                                                │
│  • 每帧: 640 字节 (20ms)                                       │
│  • 不丢弃静音帧 (保留完整上下文)                                │
│  • 实时显示剩余时间                                             │
│  • 实时显示音量电平                                             │
└───────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────┐
│ 3. 用户停止录音     │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 4. PCM 转 WAV      │  添加 WAV 文件头 (44 字节)
└─────────┬─────────┘
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│ 5. Base64 编码并构建请求                                       │
│                                                                │
│  {                                                              │
│    "model": "qwen3-asr-flash",                                 │
│    "stream": true,                                             │
│    "messages": [{                                              │
│      "role": "user",                                           │
│      "content": [{                                             │
│        "type": "input_audio",                                  │
│        "input_audio": {                                        │
│          "data": "data:audio/wav;base64,{base64Wav}",          │
│          "format": "wav"                                       │
│        }                                                       │
│      }]                                                        │
│    }],                                                         │
│    "asr_options": {                                            │
│      "language": "zh",                                         │
│      "enable_itn": false                                       │
│    }                                                           │
│  }                                                              │
└───────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────┐
│ 6. HTTP POST 请求  │  URL: /compatible-mode/v1/chat/completions
└─────────┬─────────┘  Accept: text/event-stream
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│ 7. SSE 流式响应解析                                            │
│                                                                │
│  data: {"choices": [{                                         │
│    "delta": {"content": "第一段文字..."}                       │
│  }]}                                                            │
│                                                                │
│  data: {"choices": [{                                         │
│    "delta": {"content": "后续文字..."}                         │
│  }]}                                                            │
│                                                                │
│  data: [DONE]                                                  │
└───────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────┐
│ 8. 累积文本并实时   │  每收到一个 delta 就更新显示
│    更新显示        │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ 9. 流结束或超时     │  超时: 90 秒
└─────────┬─────────┘
          │
          ▼
    完成转写，复制到剪贴板
```

### 核心代码: FileASRStreamClient

```swift
// 文件: Sources/FileASRStreamClient.swift

// 启动文件 ASR
func start(base64Wav: String) {
    let audioDataURI = "data:audio/wav;base64,\(base64Wav)"
    let payload: [String: Any] = [
        "model": model,
        "stream": true,
        "messages": [[
            "role": "user",
            "content": [[
                "type": "input_audio",
                "input_audio": [
                    "data": audioDataURI,
                    "format": "wav"
                ]
            ]]
        ]],
        "asr_options": [
            "language": language,
            "enable_itn": false
        ]
    ]

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.addValue("text/event-stream", forHTTPHeaderField: "Accept")

    let task = session.dataTask(with: req)
    task.resume()
}

// SSE 解析
private func parseSSE() {
    while let range = buffer.range(of: Data("\n".utf8)) {
        let lineData = buffer.subdata(in: 0..<range.lowerBound)
        buffer.removeSubrange(0..<range.upperBound)

        var line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces)
        guard line?.hasPrefix("data:") == true else { continue }

        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            onDone?()
            return
        }

        // 解析 JSON: {"choices": [{"delta": {"content": "..."}}]}
        if let obj = try? JSONSerialization.jsonObject(with: payload.data()),
           let choices = obj["choices"] as? [[String: Any]],
           let content = choices.first?["delta"] as? [String: Any]?["content"] as? String {
            onDelta?(content)
        }
    }
}
```

### WAV 编码

```swift
// 文件: Sources/WavEncoder.swift

func makeWav(pcm16Mono16k pcm: Data, sampleRate: Int, channels: Int) -> Data {
    var out = Data()

    // RIFF header
    out.append("RIFF".data(using: .ascii)!)
    out.append(Int32(36 + pcm.count).littleEndian)
    out.append("WAVE".data(using: .ascii)!)

    // fmt chunk
    out.append("fmt ".data(using: .ascii)!)
    out.append(Int32(16).littleEndian)           // chunk size
    out.append(Int16(1).littleEndian)            // audio format (PCM)
    out.append(Int16(channels).littleEndian)
    out.append(Int32(sampleRate).littleEndian)
    out.append(Int32(sampleRate * channels * 2).littleEndian)  // byte rate
    out.append(Int16(channels * 2).littleEndian) // block align
    out.append(Int16(16).littleEndian)           // bits per sample

    // data chunk
    out.append("data".data(using: .ascii)!)
    out.append(Int32(pcm.count).littleEndian)
    out.append(pcm)

    return out
}
```

---

## 音频采集系统

### AudioCapture 统一入口

两种模式共享同一套音频采集系统，但行为略有不同：

```swift
// 文件: Sources/AudioCapture.swift

// 核心常量
let kSampleRate: Double = 16_000      // 采样率: 16kHz
let kChannels: AVAudioChannelCount = 1  // 声道: 单声道
let kFrameMS = 20                      // 帧长: 20ms
let kFrameBytes = 640                  // 帧字节数: 640
let kSilenceThreshold: Int32 = 220     // 静音阈值

// 启动采集
func start(dropSilenceFrames: Bool = true, frameHandler: @escaping (Data) -> Void) {
    // 实时模式: dropSilenceFrames = true (丢弃静音帧)
    // 文件模式: dropSilenceFrames = false (保留所有帧)

    let input = engine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)

    // 目标格式: 16kHz, 16-bit, 单声道
    let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                              sampleRate: 16000,
                              channels: 1,
                              interleaved: true)

    let converter = AVAudioConverter(from: inputFormat, to: target)

    input.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { buffer, _ in
        // 格式转换: 系统格式 → 16kHz PCM
        converter.convert(to: outBuffer) { _, status in
            status.pointee = .haveData
            return buffer
        }

        // 提取 PCM 数据
        let pcmData = Data(bytes: outBuffer.int16ChannelData[0],
                          count: outBuffer.frameLength * 2)

        // 静音检测 (可选)
        if !dropSilenceFrames || isVoice(pcmData) {
            frameHandler(pcmData)
        }
    }

    engine.start()
}
```

### 音量电平计算

```swift
// RMS (均方根) 计算，用于 UI 音量条
private func calculateRMS(_ frame: Data) -> Float {
    return frame.withUnsafeBytes { raw in
        let samples = raw.bindMemory(to: Int16.self)
        var sumSquares: Float = 0.0
        for sample in samples {
            let f = Float(sample) / Float(Int16.max)
            sumSquares += f * f
        }
        let rms = sqrt(sumSquares / Float(samples.count))
        return min(rms * 5.0, 1.0)  // 放大 5 倍用于 UI
    }
}
```

---

## 双模式对比

| 特性 | 实时流式模式 | 文件闪传模式 |
|------|-------------|-------------|
| **快捷键** | ⌥ + Space | ⌥ + ← |
| **协议** | WebSocket | HTTP POST (SSE) |
| **API 端点** | `wss://dashscope.aliyuncs.com/api-ws/v1/realtime` | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` |
| **模型** | `qwen3-asr-flash-realtime` | `qwen3-asr-flash` |
| **首字延迟** | < 100ms | 1-3s |
| **音频处理** | 流式发送 | 采集完成后一次性发送 |
| **静音帧** | 自动丢弃 | 保留 |
| **最大时长** | 无限制 (自动停) | 5 分钟 |
| **网络断线** | 自动重连 (最多 2 次) | 保留 WAV 支持重试 |
| **精度** | 流式近似 | 全量分析，精度更高 |
| **典型场景** | 即时通讯、邮件、代码注释 | 会议纪要、讲座、长篇口述 |

---

## 错误处理与容错

### 实时模式容错

```swift
// 自动重连机制
private func tryReconnectRealtime(reason: String) {
    guard reconnectAttempts < maxReconnectAttempts else {
        beginStopping(reason: "重连失败")
        return
    }
    reconnectAttempts += 1

    // 等待后重连
    let wait = Double(reconnectAttempts)
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
        // 重新建立 WebSocket 连接
        let client = ASRWebSocketClient(...)
        client.connect()
    }
}
```

### 文件模式容错

```swift
// 保存失败的音频用于重试
private func doStartFileASRStreaming() {
    let wav = makeWav(pcm16Mono16k: recordedPCM, ...)

    // 保存到临时目录
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("FlashASR-failed-\(timestamp).wav")
    try? wav.write(to: tmpURL)
    lastFailedFileAudioURL = tmpURL

    // 上传
    client.start(base64Wav: wav.base64EncodedString())
}

// 重试功能
func retryLastFailedFileUpload() {
    guard let url = lastFailedFileAudioURL,
          let wav = try? Data(contentsOf: url) else {
        return
    }
    // 重新上传
    client.start(base64Wav: wav.base64EncodedString())
}
```

---

## 附录: API 接口规范

### 实时 ASR WebSocket 协议

**连接 URL:**
```
wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime
```

**请求头:**
```
Authorization: Bearer {apiKey}
OpenAI-Beta: realtime=v1
```

**发送消息格式:**
```json
{
  "event_id": "event_1234567890_1234",
  "type": "input_audio_buffer.append",
  "audio": "base64编码的PCM数据"
}
```

**接收事件类型:**
- `session.created` - 会话创建
- `input_audio_buffer.speech_started` - 语音开始
- `input_audio_buffer.speech_stopped` - 语音结束
- `conversation.item.input_audio_transcription.text` - 中间结果
- `conversation.item.input_audio_transcription.completed` - 最终结果
- `session.finished` - 会话结束

### 文件 ASR HTTP 协议

**请求 URL:**
```
POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
```

**请求头:**
```
Authorization: Bearer {apiKey}
Content-Type: application/json
Accept: text/event-stream
```

**请求体:**
```json
{
  "model": "qwen3-asr-flash",
  "stream": true,
  "messages": [{
    "role": "user",
    "content": [{
      "type": "input_audio",
      "input_audio": {
        "data": "data:audio/wav;base64,{base64Wav}",
        "format": "wav"
      }
    }]
  }],
  "asr_options": {
    "language": "zh",
    "enable_itn": false
  }
}
```

**响应格式 (SSE):**
```
data: {"choices": [{"delta": {"content": "转写文字..."}}]}

data: [DONE]
```

---

*文档版本: 4.5.0*
*最后更新: 2025-02*
