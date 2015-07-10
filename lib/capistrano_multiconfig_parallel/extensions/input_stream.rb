module CapistranoMulticonfigParallel
  class InputStream
    def self.hook(actor)
      $stdin = new($stdin, actor)
    end

    def self.unhook
      $stdin.finish if $stdin.is_a? CapistranoMulticonfigParallel::InputStream
      $stdin = STDIN
    end

    def initialize(real_stdin, actor)
      @real = real_stdin
      @actor = actor
    end

    def gets(*args)
     input = @actor.wait_for_stdin_input
      input
    end

    def finish
     
    end

    def method_missing(name, *args, &block)
      @real.send name, *args, &block
    end
  end
end

