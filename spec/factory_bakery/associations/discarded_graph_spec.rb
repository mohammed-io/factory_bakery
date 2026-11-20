# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

RSpec.describe 'FactoryBakery discarded association graphs' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :all
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  it 'builds the polymorphic parent without generating its typed aliases' do
    article = define_model('DiscardArticle', title: :string)
    photo = define_model('DiscardPhoto', caption: :string)
    event = define_model('DiscardEvent', subject_id: { type: :integer, null: false }, subject_type: :string) do
      belongs_to :subject, polymorphic: true, optional: false
      belongs_to :article, foreign_key: :subject_id, class_name: 'DiscardArticle', optional: true
      belongs_to :photo, foreign_key: :subject_id, class_name: 'DiscardPhoto', optional: true
      validates :subject_type, inclusion: { in: ['DiscardArticle'] }
    end

    record = FactoryBakery.bake!(event)

    expect(record.reload.subject).to be_a(article)
    expect(article.count).to eq(1)
    expect(photo.count).to eq(0)
  end

  it 'rolls back the fresh subtree when the edge adopts an existing read-only row' do
    writer = define_model('DiscardWriter', name: :string)
    detail = define_model('DiscardDetail', name: :string)
    view = define_model('DiscardView', writer_id: :integer, detail_id: :integer) do
      belongs_to :writer, class_name: 'DiscardWriter', optional: false
      belongs_to :detail, class_name: 'DiscardDetail', optional: false
      define_method(:readonly?) { true }
    end
    view.insert_all!([{ writer_id: nil, detail_id: nil }])
    FactoryBakery.define(view) { writer { FactoryBakery.bake!(writer) } }
    owner = define_model('DiscardViewOwner', view_id: :integer) do
      belongs_to :view, class_name: 'DiscardView', optional: false
    end

    record = FactoryBakery.bake!(owner)

    expect(record.reload.view.id).to eq(view.first.id)
    expect(writer.count).to eq(0)
    expect(detail.count).to eq(0)
  end

  it 'accepts a validation callback replacing an automatic parent with a persisted row' do
    profile = define_model('DiscardSenderProfile', bio: :string)
    account = define_model('DiscardSender', name: :string, profile_id: :integer) do
      belongs_to :profile, class_name: 'DiscardSenderProfile', optional: false
    end
    sender = account.create!(name: 'Existing sender', profile: profile.create!)
    event = define_model('DiscardSenderEvent', sender_id: { type: :integer, null: false }) do
      belongs_to :sender, class_name: 'DiscardSender', optional: true
      before_validation { self.sender_id = DiscardSender.first.id }
    end

    record = FactoryBakery.bake!(event)

    expect(record.reload.sender).to eq(sender)
    expect(account.count).to eq(1)
    expect(profile.count).to eq(1)
  end

  it 'still rejects a superseded parent that another retained edge needs' do
    sender = define_model('DiscardSharedSender', name: :string)
    sender.create!(name: 'Existing sender')
    event = define_model('DiscardSharedEvent', sender_id: :integer, backup_sender_id: :integer) do
      belongs_to :sender, class_name: 'DiscardSharedSender', optional: false
      belongs_to :backup_sender, class_name: 'DiscardSharedSender', optional: true, autosave: false
      before_validation do
        self.backup_sender ||= self.sender
        self.sender_id = DiscardSharedSender.first.id
      end
    end
    FactoryBakery.define(event) { skip :backup_sender }

    expect { FactoryBakery.bake!(event) }
      .to raise_error(FactoryBakery::IncompletePersistenceError, /DiscardSharedSender.*backup_sender/)
    expect(event.count).to eq(0)
  end

  it 'accepts a validation callback explicitly clearing an automatic optional parent' do
    role = define_model('DiscardDefaultRole', name: :string)
    user = define_model('DiscardDefaultUser', role_id: :integer) do
      belongs_to :role, class_name: 'DiscardDefaultRole', optional: true
      before_validation { self.role = nil }
    end

    record = FactoryBakery.bake!(user)

    expect(record.reload.role).to be_nil
    expect(role.count).to eq(0)
  end

  it 'still rejects a user-declared parent displaced by a callback' do
    sender = define_model('DiscardDeclaredSender', name: :string)
    sender.create!(name: 'Existing sender')
    event = define_model('DiscardDeclaredEvent', sender_id: :integer) do
      belongs_to :sender, class_name: 'DiscardDeclaredSender', optional: false
      before_validation { self.sender_id = DiscardDeclaredSender.first.id }
    end
    FactoryBakery.define(event) { sender { FactoryBakery.bake(DiscardDeclaredSender) } }

    expect { FactoryBakery.bake!(event) }
      .to raise_error(FactoryBakery::IncompletePersistenceError, /DiscardDeclaredSender/)
    expect(event.count).to eq(0)
  end

  it 'discards an invalid optional child and its nested bakes' do
    writer = define_model('DiscardChildWriter', name: :string)
    detail = define_model('DiscardChildDetail', name: :string)
    owner = define_model('DiscardChildOwner', name: :string) do
      has_many :children, class_name: 'DiscardInvalidChild', foreign_key: :owner_id, inverse_of: :owner
    end
    child = define_model('DiscardInvalidChild', owner_id: :integer, writer_id: :integer, detail_id: :integer) do
      belongs_to :owner, class_name: 'DiscardChildOwner', optional: false, inverse_of: :children
      belongs_to :writer, class_name: 'DiscardChildWriter', optional: false
      belongs_to :detail, class_name: 'DiscardChildDetail', optional: false
      validate { errors.add(:base, 'always invalid') }
    end
    FactoryBakery.define(child) { writer { FactoryBakery.bake!(DiscardChildWriter) } }

    record = FactoryBakery.bake!(owner)

    expect(record.reload.children).to be_empty
    expect(writer.count).to eq(0)
    expect(detail.count).to eq(0)
  end

  it 'rolls back only the lean attempt when fallback rebuilds a definition with a nested bake!' do
    writer = define_model('DiscardLeanWriter', name: :string)
    article = define_model('DiscardLeanArticle', writer_id: :integer, title: :string) do
      belongs_to :writer, class_name: 'DiscardLeanWriter', optional: false
      validate { errors.add(:title, 'is required') if title.blank? }
    end
    FactoryBakery.define(article) { writer { FactoryBakery.bake!(DiscardLeanWriter) } }

    record = FactoryBakery.bake!(article)

    expect(record.reload.title).to be_present
    expect(writer.pluck(:id)).to eq([record.writer_id])
  end
end
