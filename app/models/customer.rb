class Customer < ActiveRecord::Base
  include RequiredFieldValidatorModule 
  before_validation :generate_uuid_token, on: :create

  acts_as_paranoid # soft delete

  has_and_belongs_to_many :authorized_providers, -> { where("inactivated_date is NULL and (customer_nonsharable is NULL or customer_nonsharable != ?)", true) }, :class_name => 'Provider', :through => 'customers_providers'

  belongs_to :provider, -> { with_deleted }
  belongs_to :address
  has_many   :addresses, :dependent => :destroy, inverse_of: :customer
  belongs_to :mobility, -> { with_deleted }
  belongs_to :default_funding_source, -> { with_deleted }, :class_name=>'FundingSource'
  has_many   :trips, :dependent => :destroy, inverse_of: :customer
  has_many   :donations, :dependent => :destroy, inverse_of: :customer

  has_many  :eligibilities, through: :customer_eligibilities
  has_many  :customer_eligibilities

  # profile photo
  has_one  :photo, class_name: 'Image', as: :imageable, dependent: :destroy, inverse_of: :imageable
  accepts_nested_attributes_for :photo

  belongs_to :service_level, -> { with_deleted }
  delegate :name, to: :service_level, prefix: :service_level, allow_nil: true

  validates_presence_of :first_name
  validates_associated :address
  validates_associated :photo
  #validate :address_required
  # Token is auto-generated at database level via uuid extension
  
  accepts_nested_attributes_for :address

  normalize_attribute :first_name, :with=> [:squish, :titleize]
  normalize_attribute :last_name, :with=> [:squish, :titleize]
  normalize_attribute :middle_initial, :with=> [:squish, :upcase]

  default_scope { order('last_name, first_name, middle_initial') }
  
  scope :by_letter,    -> (letter) { where("lower(last_name) LIKE ?", "#{letter.downcase}%") }
  scope :for_provider, -> (provider_id) { where("provider_id = ? OR id IN (SELECT customer_id FROM customers_providers WHERE provider_id = ?)", provider_id, provider_id) }
  scope :individual,   -> { where(:group => false) }
  scope :active,       -> { where(inactivated_date: nil) }

  has_paper_trail

  def name
    if group
      return "(Group) %s" % first_name
    end
    if middle_initial.present?
      return "%s %s. %s" % [first_name, middle_initial, last_name]
    else
      return "%s %s" % [first_name, last_name]
    end
  end

  def active?
    !inactivated_date
  end

  def age_in_years
    return nil if birth_date.nil?
    today = Date.today
    years = today.year - birth_date.year #2011 - 1980 = 31
    if today.month < birth_date.month  || today.month == birth_date.month and today.day < birth_date.day #but 4/8 is before 7/3, so age is 30
      years -= 1
    end
    return years
  end
  
  def as_autocomplete
    { 
      :label                     => name, 
      :id                        => id,
      :group                     => group,
      :message                   => message.try(:strip)
    }
  end

  def trip_related_data
    # only return geocoded address
    if address.present? && address.the_geom.present?
      address_text = address.text.gsub(/\s+/, ' ')
      address_id = address.id
      address_data = address.attributes
      address_data[:label] = address_text
    end

    { :id                        => id,
      :label                     => name, 
      :medicaid_eligible         => is_medicaid_eligible?,
      :phone_number_1            => phone_number_1, 
      :phone_number_2            => phone_number_2,
      :mobility_notes            => mobility_notes,
      :mobility_id               => mobility_id,
      :address                   => address_text,
      :address_id                => address_id,
      :private_notes             => private_notes,
      :address_data              => address_data,
      :default_funding_source_id => default_funding_source_id,
      :default_service_level     => service_level_name,
      :customer_eligibilities    => customer_eligibilities.specified.as_json
    }
  end

  def is_medicaid_eligible?
    customer_eligibilities.includes(:eligibility).references(:eligibility).where(eligibilities: {code: 'nemt_eligible'}, eligible: true).first.present?
  end
  
  def replace_with!(other_customer_id)
    if other_customer_id.present? && self.class.exists?(other_customer_id.to_i) && id != other_customer_id.to_i
      self.trips.each do |trip|
        trip.update_attribute :customer_id, other_customer_id
      end
      
      # reload the trips array so we don't destroy the still-attached dependents
      self.trips(true)
      
      self.destroy
      self.class.find other_customer_id
    else
      false
    end
  end

  def authorized_for_provider provider_id
    !Customer.for_provider(provider_id).where("id = ?", self.id).empty?
  end

  def self.by_term( term, limit = nil )
    return Customer if term.blank?
    
    if term[0].match /\d/ #by phone number
      query = term.gsub("-", "")
      query = query[1..-1] if query.start_with? "1"
      return Customer.where([
      "regexp_replace(phone_number_1, '[^0-9]', '') = ? or
      regexp_replace(phone_number_2, '[^0-9]', '') = ?
      ", query, query])
    else
      if term.match /^[a-z]+$/i
        #a single word, either a first or a last name
        query, args = make_customer_name_query("first_name", term)
        lnquery, lnargs = make_customer_name_query("last_name", term)
        query += " or " + lnquery
        args += lnargs
      elsif term.match /^[a-z]+[ ,]\s*$/i
        comma = term.index(",")
        #a single word, either a first or a last name, complete
        term.gsub!(",", "")
        term = term.strip
        if comma
          query, args = make_customer_name_query("last_name", term, :complete)
        else
          query, args = make_customer_name_query("first_name", term, :complete)
        end
      elsif term.match /^[a-z]+\s+[a-z]$/i
        #a first name followed by either a middle initial or the first
        #letter of a last name

        first_name, last_name = term.split(" ").map(&:strip)

        query, args = make_customer_name_query("first_name", first_name, :complete)
        lnquery, lnargs = make_customer_name_query("last_name", last_name)
        miquery, miargs = make_customer_name_query("middle_initial", last_name, :initial)

        query += " and (" + lnquery +  " or " + miquery + ")"
        args += lnargs + miargs

      elsif term.match /^[a-z]+\s+[a-z]{2,}$/i
        #a first name followed by two or more letters of a last name

        first_name, last_name = term.split(" ").map(&:strip)

        query, args = make_customer_name_query("first_name", first_name, :complete)
        lnquery, lnargs = make_customer_name_query("last_name", last_name)
        query += " and " + lnquery
        args += lnargs
      elsif term.match /^[a-z]+\s*,\s*[a-z]+$/i
        #a last name, a comma, some or all of a first name

        last_name, first_name = term.split(",").map(&:strip)

        query, args = make_customer_name_query("last_name", last_name, :complete)
        fnquery, fnargs = make_customer_name_query("first_name", first_name)
        query += " and " + fnquery
        args += fnargs
      elsif term.match /^[a-z]+\s+[a-z][.]?\s+[a-z]+$/i
        #a first name, middle initial, some or all of a last name

        first_name, middle_initial, last_name = term.split(" ").map(&:strip)

        middle_initial = middle_initial[0]

        query, args = make_customer_name_query("first_name", first_name, :complete)
        miquery, miargs = make_customer_name_query("middle_initial", middle_initial, :initial)

        lnquery, lnargs = make_customer_name_query("last_name", last_name)
        query += " and " + miquery + " and " + lnquery
        args += miargs + lnargs
      elsif term.match /^[a-z]+\s*,\s*[a-z]+\s+[a-z][.]?$/i
        #a last name, a comma, a first name, a middle initial

        last_name, first_and_middle = term.split(",").map(&:strip)
        first_name, middle_initial = first_and_middle.split(" ").map(&:strip)
        middle_initial = middle_initial[0]

        query, args = make_customer_name_query("first_name", first_name, :complete)
        miquery, miargs = make_customer_name_query("middle_initial", middle_initial, :initial)
        lnquery, lnargs = make_customer_name_query("last_name", last_name, :complete)
        query += " and " + miquery + " and " + lnquery
        args += miargs + lnargs
      else
        # the final catch-all 
        query, args = make_customer_name_query("first_name", term)
        lnquery, lnargs = make_customer_name_query("last_name", term)
        query += " or " + lnquery
        args += lnargs
      end

      conditions = [query] + args
      customers  = where(conditions)

      limit ? customers.limit(limit) : customers
    end
  end

  def self.make_customer_name_query(field, value, option=nil)
    value = value.downcase
    like  = "#{value}%"
    if option == :initial
      return "(LOWER(%s) = ?)" % field, [value]
    elsif option == :complete
      return "(LOWER(%s) = ? or LOWER(%s) LIKE ? )" % [field, field], [value, like]
    else
      return "(LOWER(%s) like ?)" % [field], [like]
    end
  end

  def edit_addresses(address_objects, mailing_address_index)
    # remove non-existing ones
    prev_addr_ids = self.addresses.pluck(:id)
    existing_addr_ids = address_objects.select {|r| r[:id] != nil}.map{|r| r[:id]}
    Address.where(id: prev_addr_ids-existing_addr_ids).update_all(deleted_at: Time.current)

    # update addresses
    address_objects.each_with_index do |addr_hash, index|
      if addr_hash[:id]
        addr = Address.find_by_id(addr_hash[:id])
        addr.update_attributes addr_hash.except(:label, :lat, :lon)
      else
        addr = addresses.new(addr_hash.except(:label, :lat, :lon).merge(customer_id: self.try(:id)))
      end

      self.address = addr if index == mailing_address_index
    end
  end

  def edit_donations(donation_objects, user)
    # remove non-existing ones
    prev_donation_ids = donations.pluck(:id)
    existing_donation_ids = donation_objects.select {|r| r[:id] != nil}.map{|r| r[:id]}
    Donation.where(id: prev_donation_ids-existing_donation_ids).delete_all

    # update donations
    donation_objects.select {|r| r[:id].blank? }.each do |donation_hash|
      d = Donation.parse donation_hash, self, user
      d.save
    end
  end

  def edit_eligibilities(eligibility_params)
    return if !eligibility_params

    eligibility_params.each do |code, data|
      item = customer_eligibilities.includes(:eligibility).where(eligibilities: {code: code}).first
      item = CustomerEligibility.create(customer: self, eligibility: Eligibility.find_by_code(code)) if !item
    
      eligible = data["eligible"] == 'true' ? true : (data["eligible"] == 'false' ? false: nil)
      if eligible != false
        data["ineligible_reason"] = nil
      end

      item.update_attributes eligible: eligible, ineligible_reason: data["ineligible_reason"]
    end
  end

  private 

  def address_required
    if addresses.empty?
      errors.add :addresses, TranslationEngine.translate_text(:must_have_one_address)
    end
  end

  def generate_uuid_token
    self.token = SecureRandom.hex(5)
  end

end
