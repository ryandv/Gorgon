module GorgonBunny
  # Unifies Ruby standard library's Timeout (which is not accurate on
  # Ruby 1.8) and SystemTimer (the gem)
  Timeout = if RUBY_VERSION < "1.9"
              begin
                require "gorgon_bunny/system_timer"
                GorgonBunny::SystemTimer
              rescue LoadError
                Timeout
              end
            else
              Timeout
            end

  # Backwards compatibility
  # @private
  Timer = Timeout
end
