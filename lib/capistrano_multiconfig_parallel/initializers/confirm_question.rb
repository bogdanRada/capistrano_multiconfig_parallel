
module Capistrano
  # class used for configuration
  class Configuration
    # class used for confirming customized questions
    class ConfirmQuestion < Capistrano::Configuration::Question
      def question
        I18n.t(:confirm_question, key: key, default_value: default, scope: :capistrano)
      end
    end
  end
end

Capistrano::DSL::Env.class_eval do
  def ask_confirm(key, value, options = {})
    env.ask_confirm(key, value, options)
  end
end

Capistrano::Configuration.class_eval do
  def ask_confirm(key, default = nil, options = {})
    question = Capistrano::Configuration::ConfirmQuestion.new(key, default, options)
    set(key, question)
  end
end
