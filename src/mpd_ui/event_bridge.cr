module MPDUI
  class EventBridge
    getter refresh_requested : Qt6::Signal() = Qt6::Signal().new
    getter progress_requested : Qt6::Signal(Float64) = Qt6::Signal(Float64).new
    getter random_changed : Qt6::Signal(Bool) = Qt6::Signal(Bool).new
    getter repeat_changed : Qt6::Signal(Bool) = Qt6::Signal(Bool).new
    getter volume_changed : Qt6::Signal(Int32) = Qt6::Signal(Int32).new

    @refresh_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @progress_pending : Atomic(Bool) = Atomic(Bool).new(false)
    @elapsed_millis : Atomic(Int64) = Atomic(Int64).new(0_i64)
    @active : Atomic(Bool) = Atomic(Bool).new(true)

    def initialize(@app : Qt6::Application)
    end

    def reset : Nil
      @active.set(true)
      @refresh_pending.set(false)
      @progress_pending.set(false)
    end

    def shutdown : Nil
      @active.set(false)
      @refresh_pending.set(false)
      @progress_pending.set(false)
    end

    def request_refresh : Nil
      return unless @active.get
      return if @refresh_pending.swap(true)

      @app.invoke_later do
        next unless @active.get
        @refresh_pending.set(false)
        @refresh_requested.emit
      end
    end

    def request_progress(elapsed : Float64) : Nil
      return unless @active.get
      @elapsed_millis.set((elapsed * 1000.0).round.to_i64)
      return if @progress_pending.swap(true)

      @app.invoke_later do
        next unless @active.get
        @progress_pending.set(false)
        @progress_requested.emit(@elapsed_millis.get / 1000.0)
      end
    end

    def update_random(enabled : Bool) : Nil
      return unless @active.get

      @app.invoke_later { @random_changed.emit(enabled) if @active.get }
    end

    def update_repeat(enabled : Bool) : Nil
      return unless @active.get

      @app.invoke_later { @repeat_changed.emit(enabled) if @active.get }
    end

    def update_volume(volume : Int32) : Nil
      return unless @active.get

      @app.invoke_later { @volume_changed.emit(volume) if @active.get }
    end
  end
end
