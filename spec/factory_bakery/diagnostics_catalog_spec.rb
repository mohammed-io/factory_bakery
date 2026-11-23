# frozen_string_literal: true

require 'factory_bakery/active_record_mapper/rails_tasks'

RSpec.describe 'FactoryBakery diagnostics catalog' do
  root = File.expand_path('../..', __dir__)
  published = File.read(File.join(root, 'docs/diagnostics.md'))
  skill_copy = File.read(File.join(root, 'skills/factory-bakery-diagnostics/references/diagnostics.md'))

  # GitHub's heading slug: lowercase, punctuation dropped, spaces to hyphens.
  # Fenced code blocks are skipped so a code comment is never read as a heading.
  def heading_anchors(markdown)
    markdown.gsub(/^\s*```.*?^\s*```/m, '').scan(/^\#{1,6} +(.+)$/).flatten.map do |heading|
      heading.downcase.gsub(/[^\w\- ]/, '').tr(' ', '-')
    end
  end

  it 'gives every doctor hint an anchor that exists in the published catalog' do
    anchors = heading_anchors(published)
    hinted = FactoryBakery::ActiveRecordMapper::RailsTasks::HINTS.values.map(&:last)

    expect(hinted - anchors).to eq([])
  end

  it 'keeps the published catalog identical to the skill copy except for its note line' do
    note, _blank, *catalog = published.lines

    expect(note).to include('factory-bakery-diagnostics')
    # The skill copy links the docs from its own depth (`../../../docs/...`);
    # the published copy links them from docs/ (`guide/...`, `adr/...`). Strip
    # that one documented prefix so the catalog text itself stays identical.
    expect(skill_copy.gsub('(../../../docs/', '(')).to eq(catalog.join)
  end
end
