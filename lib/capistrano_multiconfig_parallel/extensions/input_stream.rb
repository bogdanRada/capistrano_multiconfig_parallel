module CapistranoMulticonfigParallel
  class InputStream
    def self.hook(actor, stringio)
      $stdin = new($stdin, actor, stringio)
    end

    def self.unhook
      $stdin.finish if $stdin.is_a? CapistranoMulticonfigParallel::InputStream
      $stdin = STDIN
    end

    attr_accessor :real, :actor, :stringio

    def initialize(real_stdin, actor, stringio)
      self.real = real_stdin
      self.actor = actor
      self.stringio = stringio
    end

    def gets(*_args)
      @stringio.rewind
      data = @stringio.read
      @actor.user_prompt_needed?(data)
    end

    def finish
    end

    def method_missing(name, *args, &block)
      @real.send name, *args, &block
    end
  end
end
