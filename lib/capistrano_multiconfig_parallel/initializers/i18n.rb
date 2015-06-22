require 'i18n'
en = {
  confirm_question: '%{key} (%{default_value}): '
}

I18n.backend.store_translations(:en, capistrano: en)

if I18n.respond_to?(:enforce_available_locales=)
  I18n.enforce_available_locales = true
end
