module CapistranoMulticonfigParallel
  class OutputStream
    def self.hook(actor)
      $stdout = new($stdout, actor)
    end

    def self.unhook
      $stdout.finish if $stdout.is_a? CapistranoMulticonfigParallel::OutputStream
      $stdout = STDOUT
    end

    attr_accessor :real, :actor, :strings

    def initialize(real_stdout, actor)
      self.real= real_stdout
      self.actor = actor
      self.strings = []
    end

    def write(*args)
      try_output_data(*args)
      @actor.user_prompt_needed?(args.join(' ')) 
    end


    def try_output_data(*args)
     data = args.join(' ')
     return if @strings.include?(data)
     @real.write(*args) 
     @real.flush
     @strings << data
   end

   def finish

   end

   def method_missing(name, *args, &block)
    @real.send name, *args, &block
  end
end
end

