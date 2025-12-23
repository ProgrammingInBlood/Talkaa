-- Conversations
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  title text,
  created_at timestamptz default now(),
  last_message_at timestamptz
);

-- Messages
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete cascade,
  author_id uuid references auth.users(id) on delete cascade,
  content text,
  media_url text,
  read_at timestamptz,
  created_at timestamptz default now()
);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- RLS: users can read/write their conversations/messages (demo: open read)
create policy "allow read conversations" on public.conversations for select using (true);
create policy "allow read messages" on public.messages for select using (true);

create policy "insert messages as authenticated" on public.messages for insert to authenticated using (true) with check (auth.uid() = author_id);
create policy "insert conversations as authenticated" on public.conversations for insert to authenticated using (true);

create policy "update own messages" on public.messages for update using (auth.uid() = author_id);

-- Call Sessions (tracks call state - single source of truth)
create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid references public.chats(id),
  caller_id uuid not null references auth.users(id),
  callee_id uuid not null references auth.users(id),
  type text not null check (type in ('audio', 'video')),
  status text not null default 'ringing' check (status in ('ringing', 'accepted', 'rejected', 'ended', 'timeout')),
  created_at timestamptz default now(),
  accepted_at timestamptz,
  ended_at timestamptz
);

alter table public.call_sessions enable row level security;

create policy "users can read their calls" on public.call_sessions 
  for select using (auth.uid() = caller_id or auth.uid() = callee_id);

create policy "users can insert calls" on public.call_sessions 
  for insert to authenticated with check (auth.uid() = caller_id);

create policy "participants can update calls" on public.call_sessions 
  for update using (auth.uid() = caller_id or auth.uid() = callee_id);

-- RTC Signals (WebRTC signaling: SDP offers/answers, ICE candidates)
create table if not exists public.rtc_signals (
  id bigserial primary key,
  session_id uuid not null references public.call_sessions(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  receiver_id uuid not null references auth.users(id),
  signal_type text not null check (signal_type in ('offer', 'answer', 'candidate', 'hangup', 'renegotiate')),
  payload jsonb not null,
  created_at timestamptz default now()
);

alter table public.rtc_signals enable row level security;

create policy "users can read signals for their calls" on public.rtc_signals 
  for select using (auth.uid() = sender_id or auth.uid() = receiver_id);

create policy "users can insert signals" on public.rtc_signals 
  for insert to authenticated with check (auth.uid() = sender_id);

-- Enable Realtime for call tables
alter publication supabase_realtime add table public.call_sessions;
alter publication supabase_realtime add table public.rtc_signals;