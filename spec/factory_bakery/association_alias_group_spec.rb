# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery association alias groups' do
  def define_account_and_user(user_columns = { account_id: :integer })
    account = define_model('Account', name: :string)
    user = define_model('User', user_columns) do
      belongs_to :account, optional: true
    end
    [account, user]
  end

  def define_post_and_comment(comment_columns = { commentable_type: :string, commentable_id: :integer })
    post = define_model('Post', title: :string)
    comment = define_model('Comment', comment_columns) do
      belongs_to :commentable, polymorphic: true, optional: true
    end
    [post, comment]
  end

  describe 'a belongs_to association name and its foreign key' do
    it 'lets a foreign-key call-site override beat a declared association without evaluating its block' do
      account_model, user_model = define_account_and_user
      calls = 0

      FactoryBakery.define(user_model) do
        account do
          calls += 1
          FactoryBakery.bake(account_model)
        end
      end

      record = FactoryBakery.bake(user_model, account_id: 999)

      expect(record.account_id).to eq(999)
      expect(calls).to eq(0)
    end

    it 'lets an association-object call-site override beat a declared foreign key without evaluating its block' do
      account_model, user_model = define_account_and_user
      account = account_model.create!(name: 'existing')
      calls = 0

      FactoryBakery.define(user_model) do
        account_id do
          calls += 1
          123
        end
      end

      record = FactoryBakery.bake(user_model, account: account)

      expect(record.account_id).to eq(account.id)
      expect(calls).to eq(0)
    end

    it 'lets an association-object call-site override beat a declared association without evaluating its block' do
      account_model, user_model = define_account_and_user
      account = account_model.create!(name: 'existing')
      calls = 0

      FactoryBakery.define(user_model) do
        account do
          calls += 1
          FactoryBakery.bake(account_model)
        end
      end

      record = FactoryBakery.bake(user_model, account: account)

      expect(record.account_id).to eq(account.id)
      expect(calls).to eq(0)
    end

    it 'lets a trait-declared association beat a base foreign-key declaration without evaluating the base block' do
      account_model, user_model = define_account_and_user
      base_calls = 0
      trait_calls = 0

      FactoryBakery.define(user_model) do
        account_id do
          base_calls += 1
          1
        end

        trait :with_account do
          account do
            trait_calls += 1
            FactoryBakery.bake(account_model, name: 'from trait')
          end
        end
      end

      record = FactoryBakery.bake(user_model, :with_account)

      expect(record.account.name).to eq('from trait')
      expect(base_calls).to eq(0)
      expect(trait_calls).to eq(1)
    end

    it 'lets a trait-declared foreign key beat a base association declaration without evaluating the base block' do
      account_model, user_model = define_account_and_user
      base_calls = 0
      trait_calls = 0

      FactoryBakery.define(user_model) do
        account do
          base_calls += 1
          FactoryBakery.bake(account_model)
        end

        trait :with_fk do
          account_id do
            trait_calls += 1
            42
          end
        end
      end

      record = FactoryBakery.bake(user_model, :with_fk)

      expect(record.account_id).to eq(42)
      expect(base_calls).to eq(0)
      expect(trait_calls).to eq(1)
    end

    it 'picks the later declaration when one trait declares both the association and its foreign key' do
      account_model, user_model = define_account_and_user
      fk_calls = 0
      assoc_calls = 0

      FactoryBakery.define(user_model) do
        trait :both do
          account_id do
            fk_calls += 1
            1
          end

          account do
            assoc_calls += 1
            FactoryBakery.bake(account_model, name: 'winner')
          end
        end
      end

      record = FactoryBakery.bake(user_model, :both)

      expect(record.account.name).to eq('winner')
      expect(fk_calls).to eq(0)
      expect(assoc_calls).to eq(1)
    end

    it 'picks the later foreign-key declaration when it comes after the association in one layer' do
      account_model, user_model = define_account_and_user
      fk_calls = 0
      assoc_calls = 0

      FactoryBakery.define(user_model) do
        trait :both do
          account do
            assoc_calls += 1
            FactoryBakery.bake(account_model)
          end

          account_id do
            fk_calls += 1
            7
          end
        end
      end

      record = FactoryBakery.bake(user_model, :both)

      expect(record.account_id).to eq(7)
      expect(assoc_calls).to eq(0)
      expect(fk_calls).to eq(1)
    end
  end

  describe 'a polymorphic association and its type/id columns' do
    it 'lets a raw type/id override beat a declared association without evaluating its block' do
      post_model, comment_model = define_post_and_comment
      post = post_model.create!(title: 't')
      calls = 0

      FactoryBakery.define(comment_model) do
        commentable do
          calls += 1
          FactoryBakery.bake(post_model)
        end
      end

      record = FactoryBakery.bake(comment_model, commentable_type: 'Post', commentable_id: post.id)

      expect([record.commentable_type, record.commentable_id]).to eq(['Post', post.id])
      expect(calls).to eq(0)
    end

    it 'sets both type and id consistently from an association-object override while suppressing a declared FK' do
      post_model, comment_model = define_post_and_comment
      post = post_model.create!(title: 't')
      calls = 0

      FactoryBakery.define(comment_model) do
        commentable_id do
          calls += 1
          999
        end
      end

      record = FactoryBakery.bake(comment_model, commentable: post)

      expect([record.commentable_type, record.commentable_id]).to eq(['Post', post.id])
      expect(calls).to eq(0)
    end

    it 'still applies a declared polymorphic association when no override touches its group' do
      post_model, comment_model = define_post_and_comment
      calls = 0

      FactoryBakery.define(comment_model) do
        commentable do
          calls += 1
          FactoryBakery.bake(post_model, title: 'declared')
        end
      end

      record = FactoryBakery.bake(comment_model)

      expect(record.commentable).to be_a(post_model)
      expect(record.commentable.title).to eq('declared')
      expect(record.commentable_type).to eq('Post')
      expect(calls).to eq(1)
    end
  end

  describe 'interaction with the remaining attributes' do
    it 'does not let an auto-filled foreign key clobber a declared association' do
      account_model, user_model = define_account_and_user({ account_id: :integer, name: :string })

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake!(account_model, name: 'declared') }
      end

      record = FactoryBakery.bake(user_model)

      expect(record.account_id).to eq(record.account.id)
      expect(record.account.name).to eq('declared')
    end

    it 'leaves attributes outside any alias group unchanged' do
      account_model, user_model = define_account_and_user({ account_id: :integer, name: :string })

      FactoryBakery.define(user_model) do
        name { 'from factory' }
        account { FactoryBakery.bake(account_model) }
      end

      record = FactoryBakery.bake(user_model, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(record.account).to be_a(account_model)
    end

    it 'does not change attribute resolution for POROs, which have no reflections' do
      model = define_class('PoroAliasUser') do
        attr_accessor :name, :account_id
      end

      FactoryBakery.define(model) do
        account_id { 5 }
        name { 'from factory' }
      end

      record = FactoryBakery.bake(model, name: 'from call site')

      expect(record.account_id).to eq(5)
      expect(record.name).to eq('from call site')
    end
  end
end
