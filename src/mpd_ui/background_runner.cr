module MPDUI
  module BackgroundRunner
    {% if flag?(:execution_context) %}
      @@context : Fiber::ExecutionContext::Parallel?

      private def self.context : Fiber::ExecutionContext::Parallel
        @@context ||= Fiber::ExecutionContext::Parallel.new("mpd-ui-background", 4)
      end
    {% end %}

    def self.run(name : String, &block : ->) : Nil
      run(name, block)
    end

    def self.run(name : String, block : Proc(Nil)) : Nil
      {% if flag?(:execution_context) %}
        context.spawn(name: name) { block.call }
      {% else %}
        Thread.new(name: name) { block.call }
      {% end %}
    end
  end
end
