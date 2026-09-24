#!/usr/bin/env bash
# ============================================================
# Railway deployment prep — চালান install.sh সফল হওয়ার পর
# ব্যবহার: bash deploy-to-railway.sh <your-github-repo-url>
# উদাহরণ: bash deploy-to-railway.sh https://github.com/jastinnelas/Erp.git
# ============================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { echo -e "\n${YELLOW}==> $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ ব্যর্থ: $1${NC}"; exit 1; }

REPO_URL="${1:-}"
[ -z "$REPO_URL" ] && fail "GitHub repo URL দিন। উদাহরণ: bash deploy-to-railway.sh https://github.com/USER/REPO.git"

APP_DIR="$HOME/buyinghouse-erp-app"
[ -f "$APP_DIR/artisan" ] || fail "প্রথমে install.sh চালিয়ে Laravel প্রজেক্ট বানান"
cd "$APP_DIR" || fail "প্রজেক্ট ফোল্ডারে যেতে ব্যর্থ"

# ------------------------------------------------------------
step "১/৬ — Procfile তৈরি (Railway কে বলে দেয় কীভাবে সার্ভার চালাতে হবে)"
# ------------------------------------------------------------
cat > Procfile << 'EOF'
web: php artisan migrate --force && php artisan serve --host=0.0.0.0 --port=$PORT
EOF
ok "Procfile তৈরি হয়েছে"

# ------------------------------------------------------------
step "২/৬ — .gitignore ঠিক করা (vendor/node_modules বাদ, কিন্তু composer.json/lock রাখা)"
# ------------------------------------------------------------
cat > .gitignore << 'EOF'
/node_modules
/public/hot
/public/storage
/public/build
/storage/*.key
/vendor
.env
.env.backup
.phpunit.result.cache
Homestead.json
Homestead.yaml
npm-debug.log
yarn-error.log
/.fleet
/.idea
/.vscode
database/database.sqlite
EOF
ok ".gitignore ঠিক হয়েছে"

# ------------------------------------------------------------
step "৩/৬ — APP_KEY জেনারেট করা (Railway env variable এ বসাতে হবে)"
# ------------------------------------------------------------
APP_KEY_VALUE=$(php artisan key:generate --show) || fail "key:generate"
ok "APP_KEY তৈরি হয়েছে (নিচে দেখুন, এটা কপি করে রাখুন)"

# ------------------------------------------------------------
step "৪/৬ — Composer production autoload optimize"
# ------------------------------------------------------------
composer install --no-dev --optimize-autoloader 2>&1 | tail -5
composer require laravel/breeze --dev --no-interaction --quiet 2>/dev/null || true
ok "Composer অপ্টিমাইজ করা হয়েছে"

# ------------------------------------------------------------
step "৫/৬ — Git init ও commit"
# ------------------------------------------------------------
if [ ! -d .git ]; then
    git init || fail "git init"
fi
git add -A || fail "git add"
git -c user.email="dev@example.com" -c user.name="Dev" commit -m "Deploy: full Laravel ERP project" --quiet || echo "(কমিট করার মতো নতুন কিছু নেই, চালিয়ে যাওয়া হলো)"
git branch -M main
ok "Git commit সম্পন্ন"

# ------------------------------------------------------------
step "৬/৬ — GitHub এ push (পুরনো কিছু থাকলে ওভাররাইট হবে)"
# ------------------------------------------------------------
git remote remove origin 2>/dev/null || true
git remote add origin "$REPO_URL" || fail "remote add"
git push -u origin main --force || fail "git push — GitHub token/login ঠিক আছে কিনা চেক করুন"
ok "GitHub এ push সম্পন্ন"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  ✅ কোড push হয়ে গেছে — এখন Railway dashboard এ যান${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Railway dashboard এ গিয়ে এই ৪টা কাজ করুন:"
echo ""
echo "1. আপনার সার্ভিসে '+ New' → 'Database' → 'Add MySQL' যোগ করুন"
echo ""
echo "2. সার্ভিসের 'Variables' ট্যাবে গিয়ে এই ভ্যারিয়েবলগুলো বসান:"
echo "   APP_KEY=$APP_KEY_VALUE"
echo "   APP_ENV=production"
echo "   APP_DEBUG=false"
echo "   DB_CONNECTION=mysql"
echo "   DB_HOST=\${{MySQL.MYSQLHOST}}"
echo "   DB_PORT=\${{MySQL.MYSQLPORT}}"
echo "   DB_DATABASE=\${{MySQL.MYSQLDATABASE}}"
echo "   DB_USERNAME=\${{MySQL.MYSQLUSER}}"
echo "   DB_PASSWORD=\${{MySQL.MYSQLPASSWORD}}"
echo ""
echo "3. Settings → 'Deploy' এ Start Command খালি রাখুন (Procfile থেকে নেবে)"
echo ""
echo "4. 'Deploy' চাপুন — Railway এবার real Laravel কোড পাবে,"
echo "   composer install নিজেই চালাবে, এবং migrate করে সার্ভার চালু করবে।"
echo ""
