# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Name-derived plausible strings, shared by the scalar StringFiller and the
    # string elements of ArrayFiller. Keeping one copy makes array elements use
    # exactly the same value logic as a plain string column.
    module PlausibleStrings
      private

      def generate_by_pattern
        case @attr_name
        when /email/
          FFaker::Internet.email
        when /phone/
          FFaker::PhoneNumber.phone_number
        when /name/
          FFaker::Name.name
        when /address|street|city/
          FFaker::Address.street_address
        when /url|website|link/
          FFaker::Internet.http_url
        when /username/
          FFaker::Internet.user_name
        when /title/
          FFaker::Lorem.word.capitalize
        when /body|description|content/
          FFaker::Lorem.sentence
        when /priority/
          rand(1..5).to_s
        else
          FFaker::Lorem.word
        end
      end
    end
  end
end
