module CapistranoMulticonfigParallel
  class OutputStream
    def self.hook(actor)
      $stdout = new($stdout, actor)
    end

    def self.unhook
      $stdout.finish if $stdout.is_a? CapistranoMulticonfigParallel::OutputStream
      $stdout = STDOUT
    end

    def initialize(real_stdout, actor)
      @real = real_stdout
      @actor = actor
    end

    def write(*args)
      @real.write(*args)
      input = @actor.user_prompt_needed?(args.join(" "))
      input
    end

    def finish
    end

    def method_missing(name, *args, &block)
      @real.send name, *args, &block
    end
  end
end

