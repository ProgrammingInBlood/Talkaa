-- Migration: Normalize avatar_url to paths only (remove full URLs)
-- This ensures a single source of truth - all avatar_url values are storage paths
-- The app will sign these paths when needed

-- Update profiles table: extract path from any full Supabase storage URLs
UPDATE profiles
SET avatar_url = 
  CASE 
    -- If it contains supabase storage URL, extract the path after /avatar/
    WHEN avatar_url LIKE '%supabase.co/storage%/avatar/%' THEN
      substring(split_part(avatar_url, '/avatar/', 2) from '^[^?]+')
    -- If it's already a path (no http), keep it as is
    WHEN avatar_url IS NOT NULL AND avatar_url NOT LIKE 'http%' THEN
      avatar_url
    -- Otherwise null it out (invalid URL)
    ELSE NULL
  END
WHERE avatar_url IS NOT NULL;

-- Update stories table: extract path from any full Supabase storage URLs for media_url
UPDATE stories
SET media_url = 
  CASE 
    WHEN media_url LIKE '%supabase.co/storage%/stories/%' THEN
      substring(split_part(media_url, '/stories/', 2) from '^[^?]+')
    WHEN media_url IS NOT NULL AND media_url NOT LIKE 'http%' THEN
      media_url
    ELSE NULL
  END
WHERE media_url IS NOT NULL;

-- Add a comment to document the convention
COMMENT ON COLUMN profiles.avatar_url IS 'Storage path only (e.g., "uuid/avatar.jpg"). App signs URLs at runtime.';
COMMENT ON COLUMN stories.media_url IS 'Storage path only (e.g., "uuid/story.jpg"). App signs URLs at runtime.';
