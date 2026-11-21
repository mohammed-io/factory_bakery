# frozen_string_literal: true

require 'factory_bakery/active_record_mapper/rails_tasks'

namespace :factory_bakery do
  desc 'Generate FactoryBakery definitions for named models or models without a definition'
  task :definitions, [:model] => :environment do |_task, args|
    FactoryBakery::ActiveRecordMapper::RailsTasks.new(Rails.application).definitions(args.to_a)
  end

  desc 'Check FactoryBakery validation and persistence for named models or all Active Record models'
  task :doctor, [:model] => :environment do |_task, args|
    FactoryBakery::ActiveRecordMapper::RailsTasks.new(Rails.application).doctor(args.to_a)
  end
end
