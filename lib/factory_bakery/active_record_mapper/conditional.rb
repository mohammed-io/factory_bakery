# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Decides whether a validator's if:/unless: conditions hold for the record
    # being baked. Unconditional validators always apply. Dirty-tracking
    # conditions describe the save that generating the attribute causes, so the
    # attribute is briefly marked changed while the conditions run. Any failure
    # while evaluating a condition treats the validator as applicable: a
    # condition must never crash a bake.
    module Conditional
      module_function

      def applies?(validator, record, attr_name)
        return true unless record

        # One bake reads the same rule several times (required-only
        # partitioning, routing, verification). Cache the outcome per triple
        # for this bake instead of calling a user-supplied condition on every
        # read. BuildContext clears the map at the top-level boundary, so
        # results never leak into another bake or another fiber.
        key = [record.object_id, validator.object_id, attr_name.to_s]
        cached = BuildContext.condition_result(key)
        return cached unless cached.nil?

        forced = force_change(record, attr_name)
        result = conditions_hold?(validator, record)
        BuildContext.record_condition_result(key, result)
        result
      rescue StandardError
        true
      ensure
        record.clear_attribute_changes([attr_name]) if forced && record.respond_to?(:clear_attribute_changes)
      end

      def conditions_hold?(validator, record)
        options = validator.options
        Array(options[:if]).all? { |condition| truthy?(condition, record) } &&
          Array(options[:unless]).none? { |condition| truthy?(condition, record) }
      end
      private_class_method :conditions_hold?

      def force_change(record, attr_name)
        return false unless record.respond_to?(:has_attribute?) && record.has_attribute?(attr_name)
        return false if record.attribute_changed?(attr_name)

        mark_change(record, attr_name)
      end
      private_class_method :force_change

      # Prefer the generated `<attr>_will_change!` method; fall back to the
      # lower-level writer, which is private on some versions of the framework.
      def mark_change(record, attr_name)
        writer = "#{attr_name}_will_change!"
        if record.respond_to?(writer)
          record.public_send(writer)
        elsif record.respond_to?(:attribute_will_change!, true)
          record.send(:attribute_will_change!, attr_name)
        else
          return false
        end
        true
      end
      private_class_method :mark_change

      def truthy?(condition, record)
        case condition
        # Rails calls Symbol conditions with `send` (private predicates are
        # common) and runs Procs against the record, passing it as the
        # argument when the Proc takes one.
        when Symbol, String then record.__send__(condition)
        when Proc
          condition.arity.zero? ? record.instance_exec(&condition) : record.instance_exec(record, &condition)
        else true
        end
      end
      private_class_method :truthy?
    end
  end
end
