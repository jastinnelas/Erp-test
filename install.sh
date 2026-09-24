#!/usr/bin/env bash
# ============================================================
# Buying House ERP — One-command installer
# চালানোর নিয়ম: bash install.sh
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/buyinghouse-erp-app"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

step() { echo -e "\n${YELLOW}==> $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() {
    echo -e "${RED}✗ ব্যর্থ হয়েছে: $1${NC}"
    echo -e "${RED}উপরের সম্পূর্ণ আউটপুট কপি করে পাঠান।${NC}"
    exit 1
}

# ------------------------------------------------------------
step "১/১২ — প্রয়োজনীয় টুলস চেক করা হচ্ছে"
# ------------------------------------------------------------
if command -v pkg >/dev/null 2>&1; then
    MISSING=""
    for tool in php composer unzip node npm python; do
        command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
    done
    if [ -n "$MISSING" ]; then
        echo "ইনস্টল করা হচ্ছে:$MISSING"
        pkg install -y $MISSING || fail "pkg install"
    fi
    if [ ! -d "$HOME/storage" ]; then
        termux-setup-storage
        sleep 2
    fi
fi
for tool in php composer unzip; do
    command -v "$tool" >/dev/null 2>&1 || fail "'$tool' ইনস্টল হয়নি, ম্যানুয়ালি ইনস্টল করুন: pkg install $tool"
done
ok "সব টুলস আছে"

# ------------------------------------------------------------
step "২/১২ — Laravel প্রজেক্ট স্ক্যাফোল্ড করা হচ্ছে"
# ------------------------------------------------------------
if [ -f "$APP_DIR/artisan" ]; then
    ok "আগে থেকেই Laravel প্রজেক্ট আছে ($APP_DIR), এই ধাপ স্কিপ করা হলো"
else
    composer create-project laravel/laravel "$APP_DIR" --no-interaction \
        || fail "composer create-project"
    ok "Laravel প্রজেক্ট তৈরি হয়েছে"
fi
cd "$APP_DIR" || fail "প্রজেক্ট ফোল্ডারে যেতে ব্যর্থ"

# ------------------------------------------------------------
step "৩/১২ — Breeze (auth) ইনস্টল করা হচ্ছে"
# ------------------------------------------------------------
if grep -q "laravel/breeze" composer.json 2>/dev/null; then
    ok "Breeze আগে থেকেই আছে, স্কিপ করা হলো"
else
    composer require laravel/breeze --dev --no-interaction || fail "composer require breeze"
    php artisan breeze:install blade --no-interaction || fail "breeze:install"
    ok "Breeze ইনস্টল হয়েছে"
fi

# ------------------------------------------------------------
step "৪/১২ — npm প্যাকেজ ও frontend build"
# ------------------------------------------------------------
npm install || fail "npm install"
ok "npm প্যাকেজ ইনস্টল হয়েছে (build পরে হবে, কাস্টম ফাইল বসানোর পর)"

# ------------------------------------------------------------
step "৫/১২ — PDF export প্যাকেজ (dompdf) ইনস্টল"
# ------------------------------------------------------------
composer require barryvdh/laravel-dompdf --no-interaction || fail "dompdf ইনস্টল"
composer require pragmarx/google2fa --no-interaction || fail "google2fa ইনস্টল"
ok "dompdf, google2fa ইনস্টল হয়েছে (AmarPay এখন সরাসরি HTTP API কল করে, আলাদা প্যাকেজ লাগে না)"

# ------------------------------------------------------------
step "৬/১২ — API layer (Sanctum) ইনস্টল করা হচ্ছে"
# ------------------------------------------------------------
if [ ! -f routes/api.php ]; then
    php artisan install:api --no-interaction || fail "install:api"
fi
ok "Sanctum ইনস্টল হয়েছে"

# ------------------------------------------------------------
step "৭/১২ — কাস্টম ERP ফাইল বসানো হচ্ছে"
# ------------------------------------------------------------
SRC="$SCRIPT_DIR/buyinghouse-erp"
[ -d "$SRC" ] || fail "buyinghouse-erp ফোল্ডার পাওয়া যায়নি ($SRC) — zip ঠিকভাবে extract হয়েছে কি?"

mkdir -p app/Http/Middleware app/Providers app/Jobs app/Mail app/Listeners

cp -f "$SRC"/app/Models/*.php app/Models/ || fail "Models কপি"
cp -rf "$SRC"/app/Http/Controllers/* app/Http/Controllers/ || fail "Controllers কপি"
cp -f "$SRC"/app/Http/Middleware/*.php app/Http/Middleware/ || fail "Middleware কপি"
cp -f "$SRC"/app/Providers/AppServiceProvider.php app/Providers/AppServiceProvider.php || fail "AppServiceProvider কপি"
cp -f "$SRC"/app/Jobs/*.php app/Jobs/ || fail "Jobs কপি"
cp -f "$SRC"/app/Mail/*.php app/Mail/ || fail "Mail কপি"
cp -rf "$SRC"/app/Modules app/Modules || fail "Modules (Phase 2: CRM/Costing/Sample) কপি"
cp -f "$SRC"/app/Listeners/*.php app/Listeners/ || fail "Listeners কপি"
cp -f "$SRC"/database/migrations/*.php database/migrations/ || fail "Migrations কপি"
cp -f "$SRC"/database/seeders/*.php database/seeders/ || fail "Seeders কপি"
cp -rf "$SRC"/resources/views/* resources/views/ || fail "Views কপি"

mkdir -p public/css
cp -f "$SRC"/public/css/*.css public/css/ 2>/dev/null || true
cp -f "$SRC"/public/css/*.js public/css/ 2>/dev/null || true

# Customer-facing Breeze layout এ toast component ইনজেক্ট করা (একবারই)
if [ -f resources/views/layouts/app.blade.php ] && ! grep -q "x-toast" resources/views/layouts/app.blade.php; then
    sed -i 's/<body class="font-sans antialiased">/<body class="font-sans antialiased">\n    <x-toast \/>/' resources/views/layouts/app.blade.php
fi
if [ -f resources/views/layouts/app.blade.php ] && ! grep -q "x-loading-script" resources/views/layouts/app.blade.php; then
    sed -i 's#</body>#    <x-loading-script />\n</body>#' resources/views/layouts/app.blade.php
fi
cp -f "$SRC"/routes/erp.php routes/erp.php || fail "routes/erp.php কপি"
cp -f "$SRC"/routes/api-erp.php routes/api-erp.php || fail "routes/api-erp.php কপি"
cp -f "$SRC"/bootstrap/app.php bootstrap/app.php || fail "bootstrap/app.php কপি"
mkdir -p config
cp -f "$SRC"/config/otp.php config/otp.php || fail "config/otp.php কপি"
cp -f "$SRC"/config/aamarpay.php config/aamarpay.php || fail "config/aamarpay.php কপি"

if ! grep -qF "require __DIR__.'/api-erp.php';" routes/api.php 2>/dev/null; then
    echo "" >> routes/api.php
    echo "require __DIR__.'/api-erp.php';" >> routes/api.php
fi

if ! grep -qF "require __DIR__.'/erp.php';" routes/web.php; then
    # Breeze এর ডিফল্ট root route ("welcome" view) সরিয়ে দেওয়া হচ্ছে,
    # নইলে সেটাই আগে match হয়ে আমাদের নতুন BuyingCore হোমপেজ (route: home)
    # কখনো দেখা যাবে না — Laravel প্রথম matching route ব্যবহার করে।
    python3 - <<'PYEOF'
import re
path = "routes/web.php"
c = open(path).read()
c = re.sub(
    r"Route::get\('/',\s*function\s*\(\)\s*\{\s*return view\('welcome'\);\s*\}\);\s*",
    "",
    c
)
open(path, "w").write(c)
PYEOF
    echo "" >> routes/web.php
    echo "require __DIR__.'/erp.php';" >> routes/web.php
fi
ok "সব কাস্টম ফাইল বসানো হয়েছে"

# ------------------------------------------------------------
step "৭.৫/১২ — Tailwind CSS build (এখন করা হচ্ছে যাতে আমাদের সব"
step "কাস্টম Blade ফাইলের ক্লাসও কম্পাইল হওয়া CSS-এ ধরা পড়ে)"
# ------------------------------------------------------------
if [ -f tailwind.config.js ] && ! grep -q "resources/views/\*\*" tailwind.config.js; then
    python3 - <<'PYEOF'
import re
path = "tailwind.config.js"
c = open(path).read()
if "resources/views/**/*.blade.php" not in c:
    c = re.sub(
        r"content:\s*\[",
        "content: [\n        './resources/views/**/*.blade.php',",
        c,
        count=1
    )
    open(path, "w").write(c)
    print("tailwind.config.js content glob ঠিক করা হয়েছে")
PYEOF
fi
npm run build || fail "npm run build"
ok "CSS build সম্পন্ন — সব কাস্টম component/page এর ক্লাস অন্তর্ভুক্ত"

# ------------------------------------------------------------
step "৮/১২ — Autoload regenerate করা হচ্ছে"
# ------------------------------------------------------------
composer dump-autoload || fail "composer dump-autoload"
ok "Autoload ঠিক আছে"

# যাচাই: সব দরকারি ক্লাস আসলেই খুঁজে পাওয়া যাচ্ছে কিনা
php -r "
require 'vendor/autoload.php';
\$classes = [
    'App\\\\Http\\\\Middleware\\\\EnsureUserHasRole',
    'App\\\\Http\\\\Middleware\\\\EnsureOtpVerified',
    'App\\\\Http\\\\Middleware\\\\EnsureTwoFactorVerified',
    'App\\\\Http\\\\Middleware\\\\SecurityHeaders',
    'App\\\\Http\\\\Controllers\\\\Admin\\\\DashboardController',
    'App\\\\Http\\\\Controllers\\\\Admin\\\\ProductController',
    'App\\\\Http\\\\Controllers\\\\Admin\\\\AuditLogController',
    'App\\\\Http\\\\Controllers\\\\Admin\\\\ExportController',
    'App\\\\Http\\\\Controllers\\\\Auth\\\\OtpController',
    'App\\\\Http\\\\Controllers\\\\Auth\\\\TwoFactorController',
    'App\\\\Http\\\\Controllers\\\\PaymentController',
    'App\\\\Modules\\\\CRM\\\\Models\\\\Lead',
    'App\\\\Modules\\\\CRM\\\\Controllers\\\\LeadController',
    'App\\\\Modules\\\\Costing\\\\Models\\\\ProductCosting',
    'App\\\\Modules\\\\Sample\\\\Models\\\\Sample',
    'App\\\\Http\\\\Controllers\\\\Site\\\\HomeController',
    'App\\\\Http\\\\Controllers\\\\Site\\\\CatalogController',
    'App\\\\Http\\\\Controllers\\\\Site\\\\TrackController',
    'App\\\\Http\\\\Controllers\\\\Site\\\\StaticPageController',
    'App\\\\Models\\\\Order',
    'App\\\\Models\\\\AuditLog',
];
\$missing = array_filter(\$classes, fn(\$c) => !class_exists(\$c));
if (\$missing) {
    fwrite(STDERR, 'নিচের ক্লাস পাওয়া যায়নি: ' . implode(', ', \$missing) . PHP_EOL);
    exit(1);
}
echo 'সব ক্লাস ঠিকভাবে লোড হয়েছে' . PHP_EOL;
" || fail "ক্লাস অটোলোড যাচাই — উপরের নাম অনুযায়ী ফাইল missing"

# ------------------------------------------------------------
step "৯/১২ — SQLite ডাটাবেস কনফিগার করা হচ্ছে"
# ------------------------------------------------------------
touch database/database.sqlite
if [ ! -f .env ]; then
    cp .env.example .env
fi
sed -i 's/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/' .env
sed -i '/^DB_HOST=/d; /^DB_PORT=/d; /^DB_DATABASE=/d; /^DB_USERNAME=/d; /^DB_PASSWORD=/d' .env
sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=database/' .env
sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' .env

# নতুন ফিচারের জন্য .env ভ্যারিয়েবল (ডিফল্টভাবে সব বন্ধ/খালি, প্রয়োজনমতো সত্যিকারের তথ্য বসান)
cat >> .env << 'ENVEOF'

# ==== OTP Verification (true করলে registration এর পর email এ কোড যাবে) ====
OTP_ENABLED=false
OTP_EXPIRY_MINUTES=10

# ==== AmarPay Payment Gateway (merchant dashboard থেকে নিন) ====
AAMARPAY_STORE_ID=
AAMARPAY_SIGNATURE_KEY=
AAMARPAY_SANDBOX=true

# ==== SMTP (আসল ইমেইল পাঠাতে চাইলে MAIL_MAILER=smtp করে এগুলো পূরণ করুন) ====
# MAIL_MAILER=smtp
# MAIL_HOST=smtp.gmail.com
# MAIL_PORT=587
# MAIL_USERNAME=
# MAIL_PASSWORD=
# MAIL_ENCRYPTION=tls
# MAIL_FROM_ADDRESS="hello@example.com"
ENVEOF
grep -q "^APP_KEY=base64" .env || php artisan key:generate || fail "key:generate"
ok "ডাটাবেস কনফিগার হয়েছে"

# ------------------------------------------------------------
step "১০/১২ — Migrate + Seed"
# ------------------------------------------------------------
php artisan migrate:fresh --seed --force || fail "migrate:fresh --seed"
ok "ডাটাবেস তৈরি ও ডেমো ডেটা বসানো হয়েছে"

php artisan storage:link 2>/dev/null || true
ok "storage:link তৈরি হয়েছে (আপলোড করা ছবি/ফাইল দেখা যাবে)"

# ------------------------------------------------------------
step "১১/১২ — Config cache পরিষ্কার করা হচ্ছে"
# ------------------------------------------------------------
php artisan config:clear
php artisan route:clear
php artisan cache:clear
ok "Cache পরিষ্কার"

# ------------------------------------------------------------
step "১২/১২ — সব ঠিক আছে!"
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  ✅ ইনস্টলেশন সম্পূর্ণ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "এখন সার্ভার চালু করতে:"
echo "   cd $APP_DIR && php artisan serve"
echo ""
echo "নতুন অর্ডার দিলে confirmation email ব্যাকগ্রাউন্ডে (queue) পাঠানো হয়।"
echo "সেটা প্রসেস করতে আলাদা টার্মিনালে চালান:"
echo "   php artisan queue:work"
echo "(email আসলে পাঠানো হবে না, log ফাইলে (storage/logs/laravel.log) লেখা থাকবে — এটাই demo এর জন্য নিরাপদ)"
echo ""
echo "API টেস্ট করতে (Postman/curl):"
echo "   POST /api/login  { \"email\": \"abc@example.com\", \"password\": \"password\" }"
echo "   GET  /api/orders (Authorization: Bearer <token> সহ)"
echo ""
echo "তারপর ব্রাউজারে খুলুন:"
echo "   http://127.0.0.1:8000/admin/dashboard   (admin panel)"
echo "   http://127.0.0.1:8000/orders             (customer panel)"
echo ""
echo "Login:"
echo "   Admin:    admin@buyinghouse.test / password"
echo "   Customer: abc@example.com / password"
echo ""
