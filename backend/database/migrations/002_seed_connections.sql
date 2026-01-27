-- Seed data for testing Admin Portal
-- Bill and Noah subscribe to each other, create some tags

-- Bill's user ID: b97f3a19-43e8-4501-9337-6d900cef67fc
-- Noah's user ID: 22c76dfb-55af-4060-a966-f31d12ec93a1
-- STEF's user ID: 00000000-0000-0000-0000-000000000001

-- Noah subscribes to Bill (active - approved)
INSERT INTO connections (id, owner_id, subscriber_id, status, request_message, status_changed_at)
VALUES (
    'a1111111-1111-1111-1111-111111111111',
    'b97f3a19-43e8-4501-9337-6d900cef67fc',  -- Bill owns
    '22c76dfb-55af-4060-a966-f31d12ec93a1',  -- Noah subscribes
    'active',
    'Hey Bill, subscribing to stay in sync on Async!',
    NOW()
);

-- Bill subscribes to Noah (active - approved)
INSERT INTO connections (id, owner_id, subscriber_id, status, request_message, status_changed_at)
VALUES (
    'a2222222-2222-2222-2222-222222222222',
    '22c76dfb-55af-4060-a966-f31d12ec93a1',  -- Noah owns
    'b97f3a19-43e8-4501-9337-6d900cef67fc',  -- Bill subscribes
    'active',
    'Subscribing back, Ginzatron!',
    NOW()
);

-- STEF subscribes to Bill (pending - for testing approval flow)
INSERT INTO connections (id, owner_id, subscriber_id, status, request_message, status_changed_at)
VALUES (
    'a3333333-3333-3333-3333-333333333333',
    'b97f3a19-43e8-4501-9337-6d900cef67fc',  -- Bill owns
    '00000000-0000-0000-0000-000000000001',  -- STEF subscribes
    'pending',
    'Requesting access to assist with development context.',
    NOW()
);

-- Create some tags for Bill
INSERT INTO tags (id, owner_id, name, color) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'b97f3a19-43e8-4501-9337-6d900cef67fc', 'Co-Developer', '#22C55E'),
    ('b2222222-2222-2222-2222-222222222222', 'b97f3a19-43e8-4501-9337-6d900cef67fc', 'VIP', '#EAB308'),
    ('b3333333-3333-3333-3333-333333333333', 'b97f3a19-43e8-4501-9337-6d900cef67fc', 'AI Assistant', '#8B5CF6');

-- Tag Noah's connection as Co-Developer and VIP
INSERT INTO connection_tags (connection_id, tag_id) VALUES
    ('a1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111'),
    ('a1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');

-- Create tags for Noah too
INSERT INTO tags (id, owner_id, name, color) VALUES
    ('c1111111-1111-1111-1111-111111111111', '22c76dfb-55af-4060-a966-f31d12ec93a1', 'Collaborator', '#3B82F6'),
    ('c2222222-2222-2222-2222-222222222222', '22c76dfb-55af-4060-a966-f31d12ec93a1', 'Priority', '#EF4444');

-- Tag Bill's subscription to Noah as Collaborator
INSERT INTO connection_tags (connection_id, tag_id) VALUES
    ('a2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111');
