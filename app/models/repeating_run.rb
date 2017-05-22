# This is a 'dumb' model. It is managed by a Run instance, which creates a 
# repeating instance of itself when instructed to. Validation is nonexistent 
# since all data should already have been vetted by the Run instance.
class RepeatingRun < ActiveRecord::Base
  include RunCore
  include RequiredFieldValidatorModule
  include RecurringRideCoordinator
  include RecurringRideCoordinatorScheduler
  include PublicActivity::Common

  has_paper_trail

  validates :comments, :length => { :maximum => 30 }
  validate :daily_name_uniqueness
  validate :repeating_name_uniqueness
  
  has_many :runs # Child runs created by this RepeatingRun's scheduler

  scope :active, -> { where("end_date is NULL or end_date >= ?", Date.today) }
  # a query to find repeating_runs that can be used to assign repeating_trips
  scope :during, -> (from_time, to_time) { where("NOT (scheduled_start_time::time <= ?) OR NOT(scheduled_end_time::time <= ?)", to_time.utc.to_s(:time), from_time.utc.to_s(:time)) }

  schedules_occurrences_with with_attributes: -> (run) {
      {
        repeat:        1,
        interval_unit: "week",
        start_date:    (run.start_date.try(:to_date) || Date.today).to_s,
        interval:      run.repetition_interval, 
        monday:        run.repeats_mondays    ? 1 : 0,
        tuesday:       run.repeats_tuesdays   ? 1 : 0,
        wednesday:     run.repeats_wednesdays ? 1 : 0,
        thursday:      run.repeats_thursdays  ? 1 : 0,
        friday:        run.repeats_fridays    ? 1 : 0,
        saturday:      run.repeats_saturdays  ? 1 : 0,
        sunday:        run.repeats_sundays    ? 1 : 0
      }
    },
    destroy_future_occurrences_with: -> (run) {
      # Be sure not delete occurrences that have already been completed.
      runs = if run.date < Date.today
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).after_today.incomplete
      else 
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).after(run.date).incomplete
      end

      schedule = run.repeating_run.schedule
      Run.transaction do
        runs.find_each do |r|
          r.destroy unless schedule.occurs_on?(r.date)
        end
      end
    },
    destroy_all_future_occurrences_with: -> (run) {
      # Be sure not delete occurrences that have already been completed.
      runs = if run.date < Date.today
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).after_today.incomplete
      else 
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).after(run.date).incomplete
      end

      runs.destroy_all
    },
    unlink_past_occurrences_with: -> (run) {
      if run.date < Date.today
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).today_and_prior.update_all "repeating_run_id = NULL"
      else 
        Run.where().not(id: run.id).repeating_based_on(run.repeating_run).prior_to(run.date).update_all "repeating_run_id = NULL"
      end
    }

  # Builds runs based on the repeating run schedule
  def instantiate!
    return unless active? # Only build runs for active schedules

    # First and last days to create new runs
    now, later = scheduler_window_start, scheduler_window_end
        
    # Transaction block ensures that no DB changes will be made if there are any errors
    RepeatingRun.transaction do
      # Potentially create a run for each schedule occurrence in the scheduler window
      for date in schedule.occurrences_between(now, later)
                
        # Skip if occurrence is outside of schedule's active window
        next unless date_in_active_range?(date.to_date)
                
        # Build a run belonging to the repeating run for each schedule 
        # occurrence that doesn't already have a run built for it.
        unless self.runs.for_date(date).exists?
          run = Run.new(
            self.attributes
              .select{ |k, v| RepeatingRun.ride_coordinator_attributes.include?(k.to_s) }
              .merge( {
                "date" => date
              } )
          )
          self.runs << run
        end
                
      end
      
      # Timestamp the scheduler to its current timestamp or the end of the
      # advance scheduling period, whichever comes last
      self.scheduled_through = [self.scheduled_through, later].compact.max
    end
  end

  def active?
    active = true

    today = Date.today
    active = false if end_date && today > end_date

    active
  end
  
  private
  
  # Determines if any daily runs overlap with this run and have the same name and provider
  def daily_name_uniqueness
    daily_overlaps = provider.runs # same provider
      .where(name: name) # same name
      .where.not(repeating_run_id: [id].compact) # not a child of this repeating run; remove nil from the list of ids to exclude
      .select {|r| date_in_active_range?(r.date) && schedule.occurs_on?(r.date)} # date is in active range and collides with schedule
    unless daily_overlaps.empty?
      errors.add(:name,  "should be unique by day and by provider among daily runs")
    end
  end

  # Determines if the schedule of this repeating run conflicts with the schedule
  # of any other repeating run with the same provider and name
  def repeating_name_uniqueness
    repeating_overlaps = provider.repeating_runs # same provider
      .where(name: name) # same name
      .where.not(id: id) # not the same record
      .select { |rr| schedule_conflicts_with?(rr) } # checks for overlap between recurrence rules
    unless repeating_overlaps.empty?
      errors.add(:name,  "should be unique by day and by provider among repeating runs")
    end
  end
  
end
