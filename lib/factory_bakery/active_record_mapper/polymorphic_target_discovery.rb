# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Discovers concrete target classes for a required polymorphic belongs_to.
    # Every framework read lives here (ADR-0001): inclusion validators on the
    # type column, inverse `as:` reflections on loaded models, an optional one-
    # time Rails eager load, and the deterministic ordering of the result. The
    # associations plugin receives only classes and source names, never a
    # reflection or a Rails constant.
    module PolymorphicTargetDiscovery
      INCLUSION_SOURCE = 'inclusion validator on %s'
      INVERSE_SOURCE = 'inverse as: reflections on loaded models'
      EAGER_LOAD_SOURCE = 'Rails.application.eager_load!'

      class << self
        # Candidate classes ordered by preference plus the sources considered,
        # cached per (class, association, eager-load flag) for the process so a
        # lazy-load scan happens once. The flag is part of the key because a
        # non-eager answer says nothing about what an eager load would find.
        # Empty results are never cached: a class defined later (or a reload)
        # can make a previously undiscoverable target discoverable.
        def call(klass, entry, eager_load:)
          key = [klass, entry.name, eager_load]
          cached = cache[key]
          return cached if cached

          discovered = discover(klass, entry, eager_load).freeze
          cache[key] = discovered unless discovered.candidates.empty?
          discovered
        end

        # Test isolation and reload safety: drop cached results and the one-time
        # eager-load flag.
        def reset!
          @cache = {}
          @eager_loaded = false
        end

        # The single descendants read, kept separate so the cache is observable
        # by stubbing this method and counting calls across bakes.
        def descendants
          return [] unless defined?(::ActiveRecord::Base)

          ::ActiveRecord::Base.descendants
        end

        private

        def cache
          @cache ||= {}
        end

        def discover(klass, entry, eager_load)
          domain = inclusion_domain(klass, entry)
          candidates = inclusion_candidates(klass, domain)
          candidates = within_domain(inverse_candidates(klass, entry.name), domain) if candidates.empty?
          if candidates.empty? && eager_load
            candidates = within_domain(eager_load_candidates(klass, entry.name), domain)
          end

          FactoryBakery::MapperRegistry::DiscoveredTargets.new(
            candidates: order(candidates), sources: sources(entry, eager_load)
          )
        end

        # A nil domain means no static restriction. An empty intersection
        # rules out every stored type, including candidates from inverses.
        def inclusion_domain(klass, entry)
          return unless klass.respond_to?(:validators_on)
          return unless defined?(::ActiveModel::Validations::InclusionValidator)

          klass.validators_on(entry.foreign_type.to_s).filter_map do |validator|
            next unless validator.is_a?(::ActiveModel::Validations::InclusionValidator)
            next if validator.options.keys.intersect?(%i[if unless on except_on])

            static_domain(validator.options[:in] || validator.options[:within])
          end.reduce(:&)
        end

        # Read literal Array and Set domains from unconditional validators.
        # Rails resolves callable domains per record and stores type strings.
        def static_domain(raw)
          return unless raw.is_a?(Array) || raw.is_a?(::Set)

          raw.select { |value| value.is_a?(String) }
        end

        def inclusion_candidates(klass, domain)
          candidates = Array(domain).filter_map { |name| constantize(name, klass) }
          within_domain(candidates, domain)
        end

        def within_domain(candidates, domain)
          return candidates unless domain

          candidates.select { |candidate| viable_candidate?(candidate, domain) }
        end

        def viable_candidate?(candidate, allowed)
          candidate.is_a?(Class) &&
            defined?(::ActiveRecord::Base) && candidate < ::ActiveRecord::Base &&
            table_exists?(candidate) &&
            allowed.include?(candidate.polymorphic_name)
        end

        # An `as:` inverse declares which child class its owner accepts. Match
        # that class against the baked class (or an ancestor/descendant for STI)
        # so a subclass picks its own owner while a base class may pick any.
        def inverse_candidates(klass, association_name)
          descendants.flat_map do |owner|
            next [] unless owner.respond_to?(:reflect_on_all_associations)

            ReflectionCache.all(owner).filter_map do |reflection|
              next unless inverse_edge?(reflection, association_name)

              declared = constantize(reflection.class_name, owner)
              owner if declared && compatible?(klass, declared)
            end
          end.uniq
        end

        def inverse_edge?(reflection, association_name)
          return false unless %i[has_one has_many].include?(reflection.macro)

          reflection.options[:as].to_s == association_name.to_s
        end

        def compatible?(klass, declared)
          klass <= declared || declared <= klass
        end

        def eager_load_candidates(klass, association_name)
          app = defined?(::Rails) && ::Rails.application
          return [] unless app.respond_to?(:eager_load!)
          return inverse_candidates(klass, association_name) if @eager_loaded

          # Set only after a successful load: a raising eager_load! must be
          # retried next time instead of silently disabling discovery.
          app.eager_load!
          @eager_loaded = true
          inverse_candidates(klass, association_name)
        end

        def order(candidates)
          candidates.uniq.sort_by do |candidate|
            [abstract?(candidate) ? 1 : 0, table_exists?(candidate) ? 0 : 1, candidate.name.to_s]
          end.freeze
        end

        def abstract?(candidate)
          candidate.respond_to?(:abstract_class?) && candidate.abstract_class?
        end

        def table_exists?(candidate)
          return false unless candidate.respond_to?(:table_exists?)

          candidate.table_exists?
        rescue StandardError
          false
        end

        # Class names arrive as strings from inclusion validators and from
        # reflections; the class that owns the edge decides how they resolve.
        # An app override of `polymorphic_class_for` (Discourse maps
        # "ChatMessage" to Chat::Message) wins, and const_get stays the
        # fallback. A name nothing resolves reads as "no candidate", which is
        # how this method behaved before.
        def constantize(name, owner = nil)
          mapped = owner.polymorphic_class_for(name.to_s) if owner.respond_to?(:polymorphic_class_for)
          mapped || Object.const_get(name.to_s)
        rescue StandardError
          nil
        end

        def sources(entry, eager_load)
          list = [format(INCLUSION_SOURCE, entry.foreign_type), INVERSE_SOURCE]
          list << if !eager_load
                    "#{EAGER_LOAD_SOURCE} (disabled by config)"
                  elsif defined?(::Rails) && ::Rails.application.respond_to?(:eager_load!)
                    EAGER_LOAD_SOURCE
                  else
                    "#{EAGER_LOAD_SOURCE} (Rails application not present)"
                  end
          list.freeze
        end
      end
    end
  end
end
