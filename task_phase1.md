# 1단계 작업 지시서: 멀티모달 API 파이프라인 확장

## Task Role
You are an expert iOS Developer implementing a Multimodal API pipeline for a local Mac mini OpenClaw server.

## Objective
Step 1: Extend the Agent (Blue mode) data pipeline to accept image inputs captured from Ray-Ban Meta glasses, structure it into an OpenAI Vision-compatible JSON payload, and ensure strict local-only transmission.

## Scope & Target Files
- Iris/Models/AgentPayload.swift (New or existing model file if applicable)
- Iris/Services/OpenClawNodeService.swift
- Iris/Views/MainChatView.swift

## Requirements & Constraints
1. **Define Multimodal Data Structure:**
   Create an `AgentAttachment` enum and `AgentPayload` struct to support future expansions (Album, iCloud, etc.):
   ```swift
   enum AgentAttachment {
       case metaCamera(UIImage)
   }
   struct AgentPayload {
       let text: String
       let attachment: AgentAttachment?
   }
   ```
2. **Implement OpenAI Vision JSON Payload (Local Only):**
   Modify OpenClawNodeService.swift to handle AgentPayload. If an image exists:
   * Downsample/compress it to JPEG (compressionQuality: 0.7) to optimize local bandwidth.
   * Convert it to a Base64 string.
   * Construct the messages body following the standard OpenAI vision format:
     [{"type": "text", "text": "..." }, {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}]
   * Enforce the Strict Local Lock rule: if the local request fails, throw .localServerUnreachable. Do not fallback to external cloud APIs.
3. **Connect to MainChatView:**
   Expose this updated method to MainChatView. Ensure that when a vision capture trigger occurs in Agent mode, it packages the snapshot and text into AgentPayload and fires it.

## Token Efficiency Rules
 * Implement ONLY the .metaCamera case in the enum for now. Leave stubs or placeholders for other attachment types.
 * Do not modify 'Iris Live' (Red mode) camera sessions.
