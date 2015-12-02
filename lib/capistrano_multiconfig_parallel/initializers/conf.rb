require 'configliere/commandline'
Configliere::Commandline.class_eval do
  def resolve!(print_help_and_exit = true)
    process_argv!
    if print_help_and_exit && self[:help]
      dump_help
    #  exit(2)
    end
    super()
    self
  end
end
