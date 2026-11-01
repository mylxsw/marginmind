# 助手语音输入

设置 → 语音输入，选择服务商，填写凭证后保存。可先点“测试连接”：测试只发送一小段静音，不打开麦克风，也不保存表单。

- **豆包实时语音识别 2.0**：支持 App ID + Access Token 或 API Key。资源类型选择实际开通的 2.0 小时版或并发版。
- **阿里云实时语音识别**：使用百炼 API Key，支持 `paraformer-realtime-v2`（默认）和 `fun-asr-realtime`。沿用 Typeflux 的百炼接口，不是需要 Appkey / 临时 Token 的旧版智能语音交互接口。默认地址为 `wss://dashscope.aliyuncs.com/api-ws/v1/inference`，可填对应地域或业务空间的 WebSocket 地址；地址与 API Key 的地域必须一致；Paraformer 目前仅支持北京地域。

在已配置模型的助手输入框点击麦克风开始说话，识别文字会实时替换光标处的选区，保留其余草稿。再次点击或按 Enter 结束录音，等待最终识别完成后可编辑、发送。Esc 或取消按钮恢复录音前的草稿；关闭面板停止录音并保留已经显示的文字。网络或麦克风出错也保留已经识别的文字。每次录音最多五分钟。

录音提示显示在输入框外部上方的等宽工具条中，间隔 8 px，不改变输入框本身的高度。录音中显示状态、计时和取消操作；连接、转文字时显示进度。没有听到声音使用普通提示，连接中断等故障提供重试和关闭；已有识别文字时提示保留。权限或配置问题提供语音设置入口，悬停提示显示详细原因。普通输入时隐藏工具条，录音按钮与发送键之间保留 8 px 间距。

凭证保存在本机钥匙串，普通配置保存在应用偏好设置。音频直接发送到所选服务商，不落盘，不经过 MarginMind 服务器。macOS 首次使用会请求麦克风权限；拒绝后可到系统设置 → 隐私与安全性 → 麦克风中开启。

## 实现与验证

使用开源 Flutter `record` 插件采集 16 kHz、16 位、单声道 PCM，Dart `WebSocket` 直连服务商。网络协议和最终结果处理移植自 Typeflux 的 `DoubaoRealtimeTranscriber.swift` 与 `AliCloudRealtimeTranscriber.swift`，无需嵌入 Swift / Go 语音服务。

豆包采用 `bigmodel_async`，启用 `enable_nonstream`，解析压缩、序号、最终包与错误包。阿里云等待 `task-started` 才发送音频，区分临时句子和确认句子，结束时补静音并接收 `task-finished` 后迟到的最后一句。两家连接均有超时，取消会关闭连接并忽略迟到的结果。

测试覆盖协议解析、本地 WebSocket 对端、最终结果延迟、录音尾部字节、权限拒绝、启动途中取消、错误清理、草稿替换与恢复、面板关闭、设置持久化和钥匙串失败。真实云端识别需要用户自己的已开通凭证验收；本仓库不包含凭证。

参考：

- [Flutter 录音与音频流](https://docs.flutter.dev/cookbook/audio/record)
- [record 插件](https://pub.dev/packages/record)
- [豆包语音 WebSocket 协议](https://docs.volcengine.com/docs/6561/2630027?lang=zh)
- [阿里云 Paraformer 实时语音识别 WebSocket](https://help.aliyun.com/zh/model-studio/websocket-for-paraformer-real-time-service)
- [阿里云 Fun-ASR 实时语音识别 WebSocket](https://help.aliyun.com/zh/model-studio/fun-asr-realtime-websocket-api)
