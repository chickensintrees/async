# Image Input with Vision Processing

**Status**: Proposed
**Author**: STEF
**Date**: 2026-01-27

## Overview

Add the ability to include images in messages, with optional AI vision processing to describe or analyze images before sending.

## User Stories

1. As a user, I want to drag-and-drop or paste images into the message input
2. As a user, I want to attach images from my filesystem via a picker button
3. As a user, I want the AI to describe my image for accessibility or context
4. As a user, I want to see a preview of attached images before sending

## Technical Design

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     ConversationView                          │
├──────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Image Preview Area (when images attached)              │  │
│  │  [thumbnail] [thumbnail] [x remove]                     │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  [📎] Message input (with drag-drop support)     [Send]│  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘

           │ (on attach)
           ▼
┌──────────────────────────────────────────────────────────────┐
│                      ImageService                             │
├──────────────────────────────────────────────────────────────┤
│  1. Validate image (size, format)                            │
│  2. Generate thumbnail for preview                           │
│  3. Upload to Supabase Storage                               │
│  4. (Optional) Send to Claude Vision for description         │
│  5. Return ImageAttachment with URL and description          │
└──────────────────────────────────────────────────────────────┘

           │ (on send)
           ▼
┌──────────────────────────────────────────────────────────────┐
│                      Message Model                            │
├──────────────────────────────────────────────────────────────┤
│  content_raw: String (text content)                          │
│  attachments: [MessageAttachment]  // NEW                    │
│    - type: "image"                                           │
│    - url: String (Supabase Storage URL)                      │
│    - thumbnail_url: String?                                  │
│    - description: String? (from Vision API)                  │
│    - width: Int, height: Int                                 │
└──────────────────────────────────────────────────────────────┘
```

### Components

#### 1. ImageService (new file)

```swift
class ImageService {
    static let shared = ImageService()

    /// Upload image to Supabase Storage
    func upload(image: NSImage, conversationId: UUID) async throws -> URL

    /// Generate thumbnail for preview
    func generateThumbnail(image: NSImage, maxSize: CGSize) -> NSImage

    /// Analyze image with Claude Vision
    func describeImage(imageData: Data) async throws -> String

    /// Validate image (size < 20MB, supported format)
    func validate(image: NSImage) throws
}
```

#### 2. MessageAttachment (new model)

```swift
struct MessageAttachment: Codable, Identifiable {
    let id: UUID
    let type: AttachmentType
    let url: String
    let thumbnailUrl: String?
    let description: String?
    let width: Int?
    let height: Int?
    let filename: String?

    enum AttachmentType: String, Codable {
        case image
        case file  // future
    }
}
```

#### 3. Database Changes

```sql
-- Add attachments column to messages
ALTER TABLE messages ADD COLUMN attachments JSONB DEFAULT '[]';

-- Create storage bucket for message attachments
INSERT INTO storage.buckets (id, name, public)
VALUES ('message-attachments', 'message-attachments', true);

-- RLS policy: authenticated users can upload to their conversations
CREATE POLICY "Users can upload to their conversations"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'message-attachments' AND
    EXISTS (
        SELECT 1 FROM conversation_participants cp
        WHERE cp.conversation_id = (storage.foldername(name))[1]::uuid
        AND cp.user_id = auth.uid()
    )
);
```

#### 4. UI Changes to ConversationView

- Add attachment button (📎) to message input
- Support drag-and-drop on message input area
- Support paste from clipboard (Cmd+V)
- Show image previews above input when images attached
- Display images in message bubbles

### Vision Processing Options

Three modes for image handling:

1. **No Processing** (default for direct mode)
   - Just upload and attach to message
   - Other users see the image as-is

2. **Describe for Accessibility**
   - Generate alt-text description
   - Stored in `description` field
   - Shown to screen readers and in hover

3. **Analyze and Summarize** (assisted mode)
   - AI analyzes image content
   - Generates summary for conversation context
   - Useful for sharing screenshots, diagrams, etc.

### Claude Vision API Integration

```swift
func describeImage(imageData: Data) async throws -> String {
    let base64 = imageData.base64EncodedString()

    let request = ClaudeRequest(
        model: "claude-sonnet-4-20250514",
        maxTokens: 500,
        messages: [
            .init(role: "user", content: [
                .image(type: "base64", mediaType: "image/png", data: base64),
                .text("Describe this image briefly and objectively. Focus on what's shown, not interpretation.")
            ])
        ]
    )

    // ... API call
}
```

### Supported Formats

- PNG
- JPEG/JPG
- GIF (static, first frame)
- WebP

### Size Limits

- Max file size: 20MB
- Max dimensions: 4096x4096
- Thumbnails: 200x200 max

## Implementation Plan

### Phase 1: Storage & Upload (MVP)
1. Add `attachments` column to messages table
2. Create Supabase Storage bucket with RLS
3. Build `ImageService` with upload functionality
4. Add attachment button to ConversationView
5. Display images in message bubbles

### Phase 2: Vision Processing
1. Add Claude Vision API integration
2. Add "Describe image" option before send
3. Store descriptions in attachment metadata

### Phase 3: Enhanced UX
1. Drag-and-drop support
2. Paste from clipboard
3. Image preview with zoom
4. Progress indicator during upload

## Open Questions

1. **Should images be processed through the AI mediator in assisted/anonymous modes?**
   - Could describe what's in the image
   - Could flag sensitive content
   - Adds latency and cost

2. **Storage retention policy?**
   - Keep forever?
   - Delete after X days?
   - Delete when conversation deleted?

3. **Compression?**
   - Compress before upload to save storage?
   - Keep original quality?

## Testing

- Unit tests for ImageService
- Integration tests for Supabase Storage
- UI tests for attachment flow
- Test with large images (boundary conditions)
- Test unsupported formats (error handling)

## Security Considerations

- Validate file types server-side (not just extension)
- Scan for malware? (depends on Supabase capabilities)
- Rate limit uploads to prevent abuse
- Sanitize filenames before storage
