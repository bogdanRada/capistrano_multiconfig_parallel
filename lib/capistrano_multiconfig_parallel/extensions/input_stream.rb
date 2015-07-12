module CapistranoMulticonfigParallel
  class InputStream
    def self.hook(actor)
      $stdin = new($stdin, actor)
    end

    def self.unhook
      $stdin.finish if $stdin.is_a? CapistranoMulticonfigParallel::InputStream
      $stdin = STDIN
    end

    attr_accessor :real, :actor

    def initialize(real_stdin, actor)
      self.real = real_stdin
      self.actor = actor
    end

    def gets(*args)
      @actor.wait_for_stdin_input
    end

    def finish
     
    end

    def method_missing(name, *args, &block)
      @real.send name, *args, &block
    end
  end
end

