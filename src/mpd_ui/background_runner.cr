module MPDUI
  module BackgroundRunner
    @@context : Fiber::ExecutionContext::Parallel?

    private def self.context : Fiber::ExecutionContext::Parallel
      @@context ||= Fiber::ExecutionContext::Parallel.new("mpd-ui-background", 4)
    end

    def self.run(name : String, &block : ->) : Nil
      run(name, block)
    end

    def self.run(name : String, block : Proc(Nil)) : Nil
      context.spawn(name: name) { block.call }
    end
  end
end
