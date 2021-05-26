# shopify
core_notes() {
  dev cd shopify;
  echo "** notes **";
  echo "rake dev:orders:generate_dummy_orders";
  echo "rake dev:shop:change_plan SHOP_ID=1 PLAN=shopify_plus";
  echo "rake dev:shop:create COUNTRY=CA ; rake dev:shop:change_plan PLAN=shopify_plus SHOP_ID=2"
  echo "rake about"
  EXEC="rake -T"
  echo "---"
  echo $EXEC
  eval $EXEC
  cd -
}

rtest () {
  nodemon --ext rb,erb --watch "components/shopify_payments/**" -x "bash -c '. /opt/dev/dev.sh && dev t $1'"
}

# sewing-kit
_wrap wtest "yarn sewing-kit test --no-graphql"

# spin
export SPINX_ENABLE_SOURCEMAPS=true

# dev
if [[ -f /opt/dev/dev.sh ]] && [[ $- == *i* ]]; then
  source /opt/dev/dev.sh
fi

# declarative-forms
df_import() {
  dev cd web
  cp -r ~/dev/declarative-form/source/ ./packages/@shopify/declarative-forms
  cd -
}

df_export() {
  dev cd web
  cp -r ./packages/@shopify/declarative-forms/ ~/dev/declarative-form/source
  git checkout source/tsconfig.json
  cd -
}