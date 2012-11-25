require 'active_support/concern'
require 'simple_states'

class Job
  class Test

    # A Job::Test goes through the following lifecycle:
    #
    #  * A newly created instance is in the `created` state.
    #  * When started it sets attributes from the payload and clears its log
    #    (relevant for re-started jobs).
    #  * When finished it sets attributes from the payload and adds tags.
    #  * On both events it notifies event handlers and then propagates the even
    #    to the build it belongs to.
    #  * It also notifies event handlers of the `log` event whenever something
    #    is appended to the log.
    module States
      extend ActiveSupport::Concern

      FINISHED_STATES      = [:finished, :passed, :failed, :errored, :canceled] # TODO remove :finished once we've updated the state column
      FINISHING_ATTRIBUTES = [:result, :state, :finished_at]

      included do
        include SimpleStates, Job::States, Travis::Event

        states :created, :queued, :started, :passed, :failed, :errored, :canceled

        event :start,  to: :started
        event :finish, to: :finished, after: :add_tags
        event :all, after: [:notify, :propagate]
      end

      def enqueue # TODO rename to queue and make it an event, simple_states should support that now
        update_attributes!(state: :queued, queued_at: Time.now.utc)
        notify(:queue)
      end

      def start(data = {})
        log.update_attributes!(content: '')
        self.started_at = data[:started_at]
        self.worker = data[:worker]
      end

      def finish(data = {})
        data.symbolize_keys.slice(*FINISHING_ATTRIBUTES).each do |key, value|
          if key.to_sym == :result
            self.state = map_legacy_result(value) || value.to_sym
          else
            send(:"#{key}=", data[key])
          end
        end
      end

      def finished?
        FINISHED_STATES.include?(state.to_sym)
      end

      def result=(result)
        Travis.logger.warn("[deprecated] trying to set #{result.inspect} to #{inspect}\n#{caller[0..2].join("\n")}")
      end

      def append_log!(chars)
        notify(:log, _log: chars)
      end

      protected

        def extract_finishing_attributes(attributes)
          extract!(attributes, *FINISHING_ATTRIBUTES)
        end

        LEGACY_RESULTS = { 0 => :passed, 1 => :failed }

        def map_legacy_result(result)
          LEGACY_RESULTS[result.to_i] if result.to_s =~ /^[\d]+$/
        end
    end
  end
end
