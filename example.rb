# frozen_string_literal: true

define_model('Dummy',
             # Basic fields for concrete validation examples
             title: :string, # presence, inclusion, length
             name: :string, # presence, length
             email: :string, # presence, length, uniqueness
             body: :text,             # absence, length
             code: :string,           # length, uniqueness

             # Numeric fields for numericality validations
             number: :integer, # numericality with all options
             score: :integer, # numericality comparisons
             rating: :decimal, # numericality with decimals
             percentage: :float, # numericality range

             # Date/Time fields for comparison validations
             start_date: :date, # comparison validations
             end_date: :date, # comparison validations

             # Fields for special validations
             password: :string, # confirmation
             password_confirmation: :string, # confirmation counterpart
             terms: :boolean, # acceptance
             age: :integer, # numericality + comparison
             status: :string, # inclusion/exclusion
             category: :string,           # inclusion
             priority: :integer,          # inclusion

             # Additional fields for concrete validations
             price: :decimal, # numericality
             quantity: :integer) do # numericality + comparison
  # ===================================================================
  # PRESENCE VALIDATIONS (Concrete rules only)
  # ===================================================================
  validates :name, presence: true, on: :create
  validates :email, presence: true, on: :create
  validates :title, presence: true, on: :create

  # ===================================================================
  # ABSENCE VALIDATIONS (Concrete rules only)
  # ===================================================================
  validates :body, absence: true, on: :create

  # ===================================================================
  # LENGTH VALIDATIONS (Concrete values only)
  # ===================================================================
  validates :name, length: { minimum: 2, maximum: 50 }
  validates :title, length: { minimum: 3, maximum: 25 }
  validates :code, length: { is: 8 }
  validates :password, length: { in: 8..128 }
  validates :email, length: { maximum: 254 }

  # ===================================================================
  # INCLUSION VALIDATIONS (Concrete arrays only)
  # ===================================================================
  validates :title, inclusion: { in: %w[user moderator admin guest] }
  validates :status, inclusion: { in: %w[active inactive pending suspended] }
  validates :category, inclusion: { in: %w[electronics clothing books home] }
  validates :priority, inclusion: { in: [1, 2, 3, 4, 5] }

  # ===================================================================
  # EXCLUSION VALIDATIONS (Concrete arrays only)
  # ===================================================================
  validates :status, exclusion: { in: %w[archived deleted] }
  validates :title, exclusion: { in: %w[superuser root admin] }

  # ===================================================================
  # NUMERICALITY VALIDATIONS (Concrete values only)
  # ===================================================================
  validates :age, numericality: true
  validates :number, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than: 1000,
    odd: true
  }
  validates :rating, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 5
  }
  validates :percentage, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }
  validates :price, numericality: { greater_than: 0 }
  validates :quantity, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    even: true
  }
  validates :score, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100,
    other_than: 50
  }

  # ===================================================================
  # UNIQUENESS VALIDATIONS (Concrete rules only)
  # ===================================================================
  validates :email, uniqueness: true
  validates :code, uniqueness: true
  validates :email, uniqueness: { case_sensitive: false }
  validates :code, uniqueness: { scope: :title }
  validates :code, uniqueness: { scope: %i[title status] }

  # ===================================================================
  # COMPARISON VALIDATIONS (Concrete values only)
  # ===================================================================
  validates :end_date, comparison: { greater_than: :start_date }
  validates :age, comparison: { greater_than_or_equal_to: 18 }
  validates :quantity, comparison: { greater_than: 0 }
  validates :price, comparison: { greater_than_or_equal_to: 0.01 }

  # ===================================================================
  # CONFIRMATION VALIDATIONS
  # ===================================================================
  validates :password, confirmation: true

  # ===================================================================
  # ACCEPTANCE VALIDATIONS
  # ===================================================================
  validates :terms, acceptance: true
  validates :terms, acceptance: { accept: 'yes' }
end
