-- Delete test@test.com user from production database
-- Run this in your DigitalOcean database console

BEGIN;

-- Check if user exists
SELECT id, email, name, account_id, created_at 
FROM users 
WHERE email = 'test@test.com';

-- Delete the user (cascade will handle related records)
DELETE FROM users WHERE email = 'test@test.com';

-- Verify deletion
SELECT 'User deleted. Remaining: ' || COUNT(*)::text 
FROM users 
WHERE email = 'test@test.com';

COMMIT;
