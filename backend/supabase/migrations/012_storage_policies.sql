-- Migration: Add storage policies for message-attachments bucket
-- Date: 2026-01-27
-- Public buckets still need INSERT/DELETE policies

-- Allow anyone to upload (for now - can restrict to authenticated users later)
CREATE POLICY "Allow public uploads" ON storage.objects
FOR INSERT TO public
WITH CHECK (bucket_id = 'message-attachments');

-- Allow anyone to update (for overwrites)
CREATE POLICY "Allow public updates" ON storage.objects
FOR UPDATE TO public
USING (bucket_id = 'message-attachments');

-- Allow anyone to delete their uploads
CREATE POLICY "Allow public deletes" ON storage.objects
FOR DELETE TO public
USING (bucket_id = 'message-attachments');
