module MPDUI
  module BackgroundTask
    private def run_background(on_success : Proc(T, Nil), on_error : Proc(Exception, Nil)? = nil, &work : -> T) : Nil forall T
      BackgroundRunner.run("mpd-ui-background") do
        begin
          result = work.call
          next if @quitting

          @qt_app.invoke_later do
            next if @quitting

            on_success.call(result)
          end
        rescue ex
          next if @quitting
          next unless on_error

          @qt_app.invoke_later do
            next if @quitting

            on_error.call(ex)
          end
        end
      end
    end
  end
end
