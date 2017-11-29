require 'active_support/concern'

module OperatingHourCore
  extend ActiveSupport::Concern

  START_OF_DAY = '01:00:00'
  END_OF_DAY = '00:59:59' # The next morning

  included do
    belongs_to :operatable, polymorphic: true

    validates_presence_of :operatable
    validate :enforce_hour_sanity

    scope :all_day, -> { where(is_all_day: true) } 
    scope :unavailable, -> { where(is_unavailable: true) } 
    scope :regular, -> { where.not("is_all_day = ? or is_unavailable = ?", true, true) } 

    # Notes:
    # - start_time and end_time should be saved as strings, and w/o TZ info

    def make_unavailable
      self.is_all_day = false
      self.is_unavailable = true
      self.start_time = nil
      self.end_time = nil
    end
    
    def make_all_day
      self.is_all_day = true
      self.is_unavailable = false
      self.start_time = '00:00'
      self.end_time = '00:00'
    end

    def make_regular_hours(start_time, end_time)
      self.is_all_day = false
      self.is_unavailable = false
      self.start_time = start_time
      self.end_time = end_time
    end
    
    def is_regular_hours?
      !is_unavailable? && !is_all_day?
    end
    
  end

  module ClassMethods  
    # Create an array of start times in UTC format
    def available_start_times(interval: 30.minutes)
      start_time = Time.zone.parse(START_OF_DAY)
      end_time = start_time.at_end_of_day
      get_times_between start_time: start_time, end_time: end_time, interval: interval
    end
    
    # Create an array of end times in UTC format
    def available_end_times(interval: 30.minutes)
      start_time = Time.zone.parse(START_OF_DAY)
      end_time = Time.zone.parse(END_OF_DAY) + 1.day # END_OF_DAY > midnight
      get_times_between start_time: start_time, end_time: end_time, interval: interval
    end
    
    def get_times_between(start_time:, end_time:, interval: 30.minutes)
      # We only need the time as a string, but we'll use some temporary Time
      # objects to help us do some simple time math. The dates returned are
      # irrelevant
      times =[]
      t = start_time
      while t < end_time
        times << t.to_s(:time_utc)
        t += interval
      end
      times
    end

    def get_available_times(interval: 30.minutes)
      first_recur_config = self.first
      if first_recur_config.is_unavailable?
        []
      elsif first_recur_config.is_all_day?
        from_time = Time.zone.parse("00:00:00")
        to_time = from_time.at_end_of_day
        get_times_between(start_time: from_time, end_time: to_time, interval: interval)
      else
        from_time = self.regular.minimum(:start_time)
        to_time = self.regular.maximum(:end_time)
        if from_time && to_time
          get_times_between(start_time: from_time, end_time: to_time, interval: interval)
        else
          []
        end
      end
    end

    def operating_for_time?(time_of_day = Time.current.strftime('%H:%M'))
      is_operating = false

      first_recur_config = self.first
      if first_recur_config.is_unavailable?
        is_operating = false
      elsif first_recur_config.is_all_day?
        is_operating = true
      else
        self.pluck(:start_time, :end_time).each do |op|
          op_start_time = op[0]
          op_end_time = op[1]
          is_covered = if op_start_time > op_end_time
            time_of_day >= op_start_time.strftime('%H:%M') || time_of_day <= op_end_time.strftime('%H:%M')
          elsif op_start_time != op_end_time
            time_of_day.between? op_start_time.strftime('%H:%M'), op_end_time.strftime('%H:%M')
          else
            false
          end

          if is_covered
            is_operating = true
            break
          end
        end
      end

      is_operating
    end

    def operating_between_time?(start_time = Time.current.strftime('%H:%M'), end_time = Time.current.strftime('%H:%M'))
      is_operating = false

      first_recur_config = self.first
      if first_recur_config.is_unavailable?
        is_operating = false
      elsif first_recur_config.is_all_day?
        is_operating = true
      else
        self.pluck(:start_time, :end_time).each do |op|
          op_start_time = op[0]
          op_end_time = op[1]

          is_covered = if op_start_time != op_end_time 
            (start_time && start_time.between?(op_start_time.strftime('%H:%M'), op_end_time.strftime('%H:%M'))) && 
            (end_time && end_time.between?(op_start_time.strftime('%H:%M'), op_end_time.strftime('%H:%M')))
          else
            false
          end

          if is_covered
            is_operating = true
            break
          end
        end
      end

      is_operating
    end
  end

  private

  def enforce_hour_sanity
    # end_time > END_OF_DAY to allow hours such as 12:00pm - 3:00am (next day)
    if is_regular_hours? and start_time >= end_time and end_time.try(:to_s, :time_utc) > END_OF_DAY
      errors.add(:end_time, 'must be later than start time.')
    end
  end

end