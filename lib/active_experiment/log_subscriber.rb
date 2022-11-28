# frozen_string_literal: true

require "active_support/log_subscriber"

module ActiveExperiment
  # == Log Subscriber
  #
  # TODO: finish documenting.
  class LogSubscriber < ActiveSupport::LogSubscriber
    def start_run(event)
      if execution_stack.any?
        experiment_logger(event) { build_message(:warn, "Nested within #{experiment_identifier(execution_stack.last)}") }
      end

      experiment_logger(event) do |experiment|
        execution_stack.push(experiment)

        info = []
        info << "Run ID: #{experiment.run_id}"
        info << "Variant: #{experiment.variant}" if experiment.variant.present?

        build_message(:info, "Running #{experiment.name} (#{info.join(", ")})", context: experiment.log_context?)
      end
    end

    def run(event)
      errored = event.payload[:exception_object]
      aborted = !errored && event.children.any? { |child| child.payload[:aborted] }

      experiment_logger(event) do |experiment|
        execution_stack.pop

        if errored
          build_message(:error, "Run failed: #{errored.class} (#{errored.message})")
        elsif aborted
          build_message(:info, "Run aborted", details: true)
        else
          variant_name = experiment.variant
          if experiment.variant_names.include?(variant_name)
            build_message(:info, "Completed running #{experiment.variant} variant", details: true)
          elsif variant_name.present?
            build_message(:error, "Run errored: unknown `#{variant_name}` variant resolved", details: true)
          else
            build_message(:error, "Run errored: no variant resolved", details: true)
          end
        end
      end
    end

    def run_run_callbacks(event)
      return if event.payload[:exception_object].present?

      experiment_logger(event) do
        if event.payload[:aborted].present?
          build_message(:info, "Aborted run callbacks", duration: true)
        else
          build_message(:debug, "Completed run callbacks", duration: true)
        end
      end
    end

    def run_segment_callbacks(event)
      return if event.payload[:exception_object].present?

      experiment_logger(event) do |experiment|
        if event.payload[:aborted].present?
          build_message(:info, "Segmented into the `#{experiment.variant}` variant", duration: true)
        else
          build_callback_message(event)
        end
      end
    end

    def run_variant_callbacks(event)
      return if event.payload[:exception_object].present?

      experiment_logger(event) do
        if event.payload[:aborted].present?
          build_message(:warn, "Aborted in variant callbacks", duration: true)
        else
          build_callback_message(event)
        end
      end
    end

    def run_variant_steps(event)
      return if event.payload[:exception_object].present?
      return unless event.payload[:aborted].present?

      experiment_logger(event) do |experiment|
        build_message(:warn, "Aborted running variant `#{experiment.variant}` steps", duration: true)
      end
    end

    def start(name, id, payload)
      super
      try("start_#{name.split(".").first}", event_stack.last)
    rescue => e
      log_exception(name, e)
    end

    private
      def experiment_logger(event, &block)
        return unless logger.present?

        experiment = event.payload[:experiment]
        result = block.call(experiment)

        return unless result.present?

        logger.send(result[:level]) do
          log = +colorized_prefix(experiment)
          log << colorized_message(result[:message], level: result[:level])
          log << colorized_duration(event, parens: true) if result[:duration]
          log << colorized_details(event) if result[:details]
          log << colorized_context(experiment) if result[:context]
          log
        end
      end

      def build_message(level, message, **kws)
        { level: level, message: message, **kws }
      end

      def build_callback_message(event)
        variant = event.payload[:variant]
        kind = event.name.split(".").first.gsub("run_", "").tr("_", " ")

        if variant.present?
          build_message(:info, "Resolved `#{variant}` variant in #{kind}", duration: true)
        else
          build_message(:debug, "Completed #{kind}", duration: true)
        end
      end

      def colorized_prefix(experiment)
        color("  #{experiment_identifier(experiment)}  ", GREEN)
      end

      def colorized_message(message, level: :info)
        case level
        when :error
          color(message, RED, true)
        when :warn
          color(message, YELLOW, true)
        else
          message
        end
      end

      def colorized_details(event)
        " (Duration:#{colorized_duration(event, parens: false)} | Allocations: #{event.allocations})"
      end

      def colorized_duration(event, parens: true)
        duration = event.duration.round(1)
        if duration > 1000
          ret = color("#{duration}ms", RED, true)
        elsif duration > 500
          ret = color("#{duration}ms", YELLOW, true)
        else
          ret = "#{duration}ms"
        end

        parens ? " (#{ret})" : " #{ret}"
      end

      def colorized_context(experiment)
        return "" unless experiment.log_context?

        " with context: #{format_context(experiment.context).inspect}"
      end

      def format_context(arg)
        case arg
        when Hash
          arg.transform_values { |value| format_context(value) }
        when Array
          arg.map { |value| format_context(value) }
        when GlobalID::Identification
          arg.to_global_id.to_s rescue arg
        else
          arg
        end
      end

      def experiment_identifier(experiment)
        "#{experiment.class.name}[#{experiment.run_key.slice(0, 8)}]"
      end

      def execution_stack
        ActiveSupport::IsolatedExecutionState[:active_experiment_log_subscriber_execution_stack] ||= []
      end

      def logger
        ActiveExperiment.logger
      end
  end
end

ActiveExperiment::LogSubscriber.attach_to(:active_experiment)
