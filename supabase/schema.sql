-- ============================================================================
-- СТИЛЬ & ОБРАЗ — ПОЛНАЯ СХЕМА НОВОГО ПРОЕКТА SUPABASE
-- (БАЗА ДАННЫХ POSTGRESQL + SUPABASE STORAGE + REALTIME + RLS)
--
-- Инструкция:
-- 1. Создайте новый проект в https://supabase.com/dashboard
-- 2. Откройте SQL Editor -> New Query -> вставьте весь этот файл и нажмите Run.
-- 3. Скопируйте Project URL и anon / publishable key из Project Settings -> API
--    и вставьте их в файл shared-data.js (или в окне «🔑 Ключи Supabase» на сайте).
-- Скрипт идемпотентный: можно безопасно запускать повторно.
-- ============================================================================

-- 1. Расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Профили пользователей (клиенты и сотрудники магазина)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT,
  full_name TEXT NOT NULL DEFAULT 'Покупатель',
  phone TEXT,
  address TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'director', 'admin', 'cashier', 'seller', 'senior_seller', 'warehouse')),
  department TEXT DEFAULT 'Торговый зал',
  is_on_shift BOOLEAN NOT NULL DEFAULT false,
  bonus_balance INT NOT NULL DEFAULT 2000,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Триггер автоматического создания профиля при регистрации в Supabase Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, role, is_on_shift)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''), split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    CASE
      WHEN NEW.raw_user_meta_data->>'role' IN ('customer', 'director', 'admin', 'cashier', 'seller', 'senior_seller', 'warehouse')
      THEN NEW.raw_user_meta_data->>'role'
      ELSE 'customer'
    END,
    CASE
      WHEN NEW.raw_user_meta_data->>'role' IN ('director', 'admin', 'cashier', 'seller', 'senior_seller', 'warehouse')
      THEN true
      ELSE false
    END
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    phone = COALESCE(NULLIF(EXCLUDED.phone, ''), public.profiles.phone),
    role = EXCLUDED.role,
    updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Категории магазина одежды «Стиль & Образ»
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  total_count INT NOT NULL DEFAULT 1420,
  sort_order INT NOT NULL DEFAULT 0
);

-- 4. Товары магазина одежды (цены в тенге ₸, фото сохраняются в Supabase Storage)
CREATE TABLE IF NOT EXISTS public.products (
  id TEXT PRIMARY KEY DEFAULT ('prod-' || extract(epoch from now())::bigint::text || '-' || substr(md5(random()::text), 1, 4)),
  sku TEXT NOT NULL DEFAULT 'WO-4509',
  category_slug TEXT NOT NULL DEFAULT 'men',
  subcategory TEXT NOT NULL DEFAULT 'Верхняя одежда',
  brand TEXT NOT NULL DEFAULT 'Nordic Shield',
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  purchase_price INT NOT NULL DEFAULT 18000,
  base_price INT NOT NULL,
  old_price INT,
  discount_percent INT NOT NULL DEFAULT 0,
  badge TEXT DEFAULT '',
  sizes JSONB NOT NULL DEFAULT '["S","M","L","XL"]'::jsonb,
  colors JSONB NOT NULL DEFAULT '[{"name":"Темно-синий","hex":"#1e293b"}]'::jsonb,
  season TEXT NOT NULL DEFAULT 'Осень-Зима ''26',
  image_url TEXT,
  gallery_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
  stock_qty INT NOT NULL DEFAULT 45,
  min_stock INT NOT NULL DEFAULT 5,
  warehouse TEXT NOT NULL DEFAULT 'Основной склад',
  is_available BOOLEAN NOT NULL DEFAULT true,
  is_published BOOLEAN NOT NULL DEFAULT true,
  is_new BOOLEAN NOT NULL DEFAULT false,
  is_sale BOOLEAN NOT NULL DEFAULT false,
  popularity INT NOT NULL DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Складской учёт (Склад и остатки)
CREATE TABLE IF NOT EXISTS public.inventory (
  id TEXT PRIMARY KEY DEFAULT ('inv-' || substr(md5(random()::text), 1, 6)),
  sku TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'Мужчинам > Верхняя одежда',
  brand TEXT NOT NULL DEFAULT 'Nordic Shield',
  sizes_list TEXT NOT NULL DEFAULT 'S, M, L, XL',
  unit TEXT NOT NULL DEFAULT 'шт',
  quantity INT NOT NULL DEFAULT 45,
  min_threshold INT NOT NULL DEFAULT 5,
  purchase_price INT NOT NULL DEFAULT 18000,
  retail_price INT NOT NULL DEFAULT 55000,
  warehouse TEXT NOT NULL DEFAULT 'Основной склад',
  supplier TEXT NOT NULL DEFAULT 'ТОО "Fashion Import KZ"',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Сотрудники и Кадры (Внутренний портал персонала)
CREATE TABLE IF NOT EXISTS public.staff_members (
  id TEXT PRIMARY KEY DEFAULT ('st-' || substr(md5(random()::text), 1, 6)),
  full_name TEXT NOT NULL,
  position TEXT NOT NULL DEFAULT 'Продавец-консультант',
  department TEXT NOT NULL DEFAULT 'Торговый зал',
  status TEXT NOT NULL DEFAULT 'on_shift' CHECK (status IN ('on_shift', 'day_off', 'vacation')),
  hours_worked INT NOT NULL DEFAULT 120,
  monthly_sales INT NOT NULL DEFAULT 2800000,
  monthly_sales_rub INT DEFAULT 0,
  plan_target INT NOT NULL DEFAULT 3500000,
  plan_percent INT NOT NULL DEFAULT 85,
  hourly_rate INT NOT NULL DEFAULT 2200,
  phone TEXT DEFAULT '+7 (707) 555-01-01',
  email TEXT DEFAULT 'staff@style-obraz.kz',
  avatar_key TEXT DEFAULT 'staff_1',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. Задачи на день и планы смены
CREATE TABLE IF NOT EXISTS public.staff_tasks (
  id TEXT PRIMARY KEY DEFAULT ('task-' || substr(md5(random()::text), 1, 6)),
  title TEXT NOT NULL,
  status_note TEXT NOT NULL DEFAULT 'В процессе',
  assignee TEXT DEFAULT '',
  is_done BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. Промокоды магазина
CREATE TABLE IF NOT EXISTS public.promo_codes (
  code TEXT PRIMARY KEY,
  discount_percent INT NOT NULL CHECK (discount_percent BETWEEN 1 AND 90),
  min_order_amount INT NOT NULL DEFAULT 0,
  description TEXT DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true
);

-- 9. Заказы покупателей и чеки POS
CREATE TABLE IF NOT EXISTS public.orders (
  id TEXT PRIMARY KEY DEFAULT ('ord-' || (extract(epoch from now()) * 1000)::bigint::text),
  order_number INT NOT NULL,
  customer_id UUID,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  customer_email TEXT DEFAULT '',
  delivery_type TEXT NOT NULL DEFAULT 'courier' CHECK (delivery_type IN ('courier', 'pickup', 'post', 'pos')),
  city TEXT DEFAULT 'Алматы',
  address TEXT,
  comment TEXT,
  payment_method TEXT NOT NULL DEFAULT 'card',
  payment_status TEXT NOT NULL DEFAULT 'paid' CHECK (payment_status IN ('paid', 'failed', 'pending', 'refunded')),
  transaction_id TEXT,
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'assembling', 'shipped', 'delivered', 'completed', 'cancelled', 'refunded')),
  promo_code TEXT,
  subtotal_amount INT NOT NULL DEFAULT 0,
  discount_amount INT NOT NULL DEFAULT 0,
  delivery_cost INT NOT NULL DEFAULT 0,
  total_amount INT NOT NULL,
  seller_name TEXT DEFAULT 'Сидоров Алексей',
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. Позиции заказа
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id TEXT NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id TEXT,
  sku TEXT,
  product_name TEXT NOT NULL,
  brand TEXT,
  size_label TEXT NOT NULL DEFAULT 'M',
  color_name TEXT NOT NULL DEFAULT 'Черный',
  quantity INT NOT NULL DEFAULT 1,
  unit_price INT NOT NULL,
  total_price INT NOT NULL
);

-- 11. Журнал платежей (Карта, Kaspi, Apple Pay, При получении)
CREATE TABLE IF NOT EXISTS public.payment_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number INT,
  customer_name TEXT,
  amount INT NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'kaspi',
  scenario TEXT NOT NULL CHECK (scenario IN ('success', 'failed')),
  bank_code TEXT NOT NULL,
  bank_message TEXT NOT NULL,
  transaction_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- SUPABASE STORAGE: Бакет product-images для хранения фотографий одежды
-- ============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Public read product-images" ON storage.objects;
CREATE POLICY "Public read product-images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Anyone upload product-images" ON storage.objects;
CREATE POLICY "Anyone upload product-images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Anyone update product-images" ON storage.objects;
CREATE POLICY "Anyone update product-images"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Anyone delete product-images" ON storage.objects;
CREATE POLICY "Anyone delete product-images"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'product-images');

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) — открытый доступ для работы с GitHub Pages
-- ============================================================================
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'profiles', 'categories', 'products', 'inventory',
    'staff_members', 'staff_tasks', 'promo_codes', 'orders', 'order_items', 'payment_logs'
  ]) LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "allow_all_%I" ON public.%I;', t, t);
    EXECUTE format('CREATE POLICY "allow_all_%I" ON public.%I FOR ALL USING (true) WITH CHECK (true);', t, t);
  END LOOP;
END $$;

-- ============================================================================
-- REALTIME (Мгновенная синхронизация между витриной клиента и порталом персонала)
-- ============================================================================
DO $$
DECLARE tbl text;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'profiles', 'products', 'inventory', 'staff_members', 'staff_tasks', 'orders', 'order_items', 'payment_logs'
  ]) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- НАЧАЛЬНЫЕ ДАННЫЕ (SEED) — Магазин одежды «Стиль & Образ» (цены в ₸)
-- ============================================================================
INSERT INTO public.categories (slug, name, total_count, sort_order) VALUES
  ('new',    'Новинки',           340,  1),
  ('women',  'Женщинам',         2150,  2),
  ('men',    'Мужчинам',         1420,  3),
  ('kids',   'Детям',             680,  4),
  ('brands', 'Бренды',            950,  5),
  ('sale',   'Распродажа %',      520,  6),
  ('sport',  'Спортивный стиль',  410,  7),
  ('shoes',  'Обувь',             790,  8)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  total_count = EXCLUDED.total_count,
  sort_order = EXCLUDED.sort_order;

INSERT INTO public.promo_codes (code, discount_percent, min_order_amount, description, is_active) VALUES
  ('STYLE15',  15, 20000, 'Скидка 15% на осеннюю коллекцию от 20 000 ₸', true),
  ('AUTUMN26', 20, 40000, 'Скидка 20% на верхнюю одежду Осень-Зима ''26', true),
  ('KASPI10',  10, 15000, 'Скидка 10% при оплате Kaspi QR / Картой', true),
  ('VIP30',    30, 80000, 'VIP-скидка 30% при заказе от 80 000 ₸', true)
ON CONFLICT (code) DO UPDATE SET
  discount_percent = EXCLUDED.discount_percent,
  min_order_amount = EXCLUDED.min_order_amount,
  description = EXCLUDED.description;

INSERT INTO public.staff_members (id, full_name, position, department, status, hours_worked, monthly_sales, monthly_sales_rub, plan_target, plan_percent, hourly_rate, phone, email, avatar_key) VALUES
  ('st-1', 'Иванов Дмитрий',   'Администратор',        'Торговый зал', 'on_shift', 128, 3420000, 550000, 3717000, 92,  2800, '+7 (701) 234-56-01', 'ivanov@style-obraz.kz',    'staff_1'),
  ('st-2', 'Петрова Анна',     'Кассир-продавец',      'Касса',        'day_off',  112, 1850000, 0,      2176000, 85,  2100, '+7 (701) 234-56-02', 'petrova@style-obraz.kz',   'staff_2'),
  ('st-3', 'Сидоров Алексей',  'Старший продавец',     'Торговый зал', 'on_shift', 134, 4100000, 0,      3900000, 105, 2600, '+7 (701) 234-56-03', 'sidorov@style-obraz.kz',   'staff_3'),
  ('st-4', 'Кузнецова Елена',  'Кладовщик',            'Склад',        'vacation',  40,       0, 0,            0, 0,   2000, '+7 (701) 234-56-04', 'kuznetsova@style-obraz.kz','staff_4'),
  ('st-5', 'Васильев Игорь',   'Продавец-консультант', 'Торговый зал', 'on_shift',  96, 2800000, 0,      3589000, 78,  2100, '+7 (701) 234-56-05', 'vasiliev@style-obraz.kz',  'staff_5'),
  ('st-6', 'Смирнова Алия',    'Продавец-консультант', 'Торговый зал', 'on_shift', 118, 3150000, 0,      3300000, 95,  2100, '+7 (701) 234-56-06', 'smirnova@style-obraz.kz',  'staff_6'),
  ('st-7', 'Нурланов Ерлан',   'Специалист склада',    'Склад',        'on_shift', 124,       0, 0,            0, 100, 2200, '+7 (701) 234-56-07', 'nurlanov@style-obraz.kz',  'staff_7'),
  ('st-8', 'Ахметова Динара',  'Кассир-консультант',   'Касса',        'on_shift', 116, 2240000, 0,      2400000, 93,  2100, '+7 (701) 234-56-08', 'akhmetova@style-obraz.kz', 'staff_8')
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  position = EXCLUDED.position,
  department = EXCLUDED.department,
  status = EXCLUDED.status,
  hours_worked = EXCLUDED.hours_worked,
  monthly_sales = EXCLUDED.monthly_sales,
  plan_percent = EXCLUDED.plan_percent;

INSERT INTO public.staff_tasks (id, title, status_note, assignee, is_done) VALUES
  ('task-1', 'Утренняя планерка и проверка готовности зала', 'Выполнено',              'Иванов Д.',  true),
  ('task-2', 'Приемка новой поставки (осенняя коллекция)',   'В процессе',             'Нурланов Е.', false),
  ('task-3', 'Обновление ценников и манекенов',              'Назначено Петрова А.',   'Петрова А.', false),
  ('task-4', 'Вечерняя инкассация и закрытие смен',          'По расписанию 21:00',    'Иванов Д.',  false)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  status_note = EXCLUDED.status_note,
  is_done = EXCLUDED.is_done;
