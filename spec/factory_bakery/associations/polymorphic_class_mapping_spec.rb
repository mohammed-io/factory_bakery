# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# An application may map a stored class name to a class of its own: Discourse
# resolves "ChatMessage" to Chat::Message through `polymorphic_class_for`.
# Target names are therefore resolved through the owning class's hook first, so
# such models bake instead of failing with NameError.
RSpec.describe 'polymorphic class mapping' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
    FactoryBakery::Associations.eager_load = false
    discovery.reset!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
    discovery.reset!
  end

  def discovery
    FactoryBakery::ActiveRecordMapper::PolymorphicTargetDiscovery
  end

  def introspection
    FactoryBakery::ActiveRecordMapper::AssociationIntrospection
  end

  # The app's shape: a name-to-class mapping consulted before Rails' own
  # constant lookup, inherited by every model that derives from the base. The
  # base is abstract so its descendants keep their own tables.
  def define_mapping_base(name, mapping)
    define_class(name, ActiveRecord::Base) do
      self.abstract_class = true

      define_singleton_method(:polymorphic_class_for) do |type_name|
        mapped = mapping[type_name.to_s]
        return Object.const_get(mapped) if mapped

        super(type_name)
      end
    end
  end

  it 'resolves a polymorphic target named by an inclusion validator through the owner mapping' do
    message = define_model('PolyMapMessage', body: :string) do
      # The type column stores what the inclusion validator lists, and the
      # app maps that name back to this class.
      def self.polymorphic_name = 'LegacyMsg'
    end
    base = define_mapping_base('PolyMapBase', 'LegacyMsg' => 'PolyMapMessage')

    create_table(:poly_map_links) do |table|
      table.string :target_type
      table.integer :target_id
    end
    link = define_class('PolyMapLink', base) do
      belongs_to :target, polymorphic: true, optional: false
      validates :target_type, inclusion: { in: %w[LegacyMsg] }
    end

    record = FactoryBakery.bake!(link)

    expect(record.target).to be_a(message)
    expect(record.target_type).to eq('LegacyMsg')
    expect(record).to be_valid
    expect(link.find(record.id).target).to be_a(message)
  end

  it 'resolves a belongs_to whose declared class name only the owner maps' do
    message = define_model('PolyMapLegacyMessage', body: :string)
    base = define_mapping_base('PolyMapSearchBase', 'LegacyMsg' => 'PolyMapLegacyMessage')

    create_table(:poly_map_searches) do |table|
      table.integer :chat_message_id
    end
    search = define_class('PolyMapSearch', base) do
      belongs_to :chat_message, class_name: 'LegacyMsg'
    end

    entry = introspection.for(search).find { |candidate| candidate.name == 'chat_message' }

    expect(entry.target_class_name).to eq('LegacyMsg')
    expect(entry.resolve_target).to be(message)
  end

  it 'still reports a resolving error when nothing maps the class name' do
    base = define_mapping_base('PolyMapUnknownBase', {})

    create_table(:poly_map_unknown_searches) do |table|
      table.integer :chat_message_id
    end
    search = define_class('PolyMapUnknownSearch', base) do
      belongs_to :chat_message, class_name: 'LegacyMsg'
    end

    entry = introspection.for(search).find { |candidate| candidate.name == 'chat_message' }

    expect { entry.resolve_target }.to raise_error(FactoryBakery::Error, /chat_message \(target "LegacyMsg"\)/)
  end
end
