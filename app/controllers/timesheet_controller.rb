class TimesheetController < ApplicationController
  unloadable

  layout 'base'
  if Rails::VERSION::MAJOR < 5  # < Rails 5
    before_action :get_list_size
    before_action :get_precision
    before_action :get_activities
  else  # >= Rails 5
    before_action :get_list_size
    before_action :get_precision
    before_action :get_activities
  end

  helper :sort
  include SortHelper
  helper :issues
  include ApplicationHelper
  helper :timelog

  SessionKey = 'timesheet_filter'

#  verify :method => :delete, :only => :reset, :render => {:nothing => true, :status => :method_not_allowed }

  def index
    load_filters_from_session
    unless @timesheet
      @timesheet ||= Timesheet.new
    end
    @timesheet.allowed_projects = allowed_projects

    if @timesheet.allowed_projects.empty?
      render :action => 'no_projects'
      return
    end
  end

  def report
    if params && params[:timesheet]
      @timesheet = Timesheet.new(params.require(:timesheet).permit!)
    else
      redirect_to :action => 'index'
      return
    end

    @timesheet.allowed_projects = allowed_projects

    if @timesheet.allowed_projects.empty?
      render :action => 'no_projects'
      return
    end

    if !params[:timesheet][:projects].blank?
      @timesheet.projects = @timesheet.allowed_projects.find_all { |project|
        params[:timesheet][:projects].include?(project.id.to_s)
      }
    else
      @timesheet.projects = @timesheet.allowed_projects
    end

    call_hook(:plugin_timesheet_controller_report_pre_fetch_time_entries, { :timesheet => @timesheet, :params => params })

    save_filters_to_session(@timesheet)

    @timesheet.fetch_time_entries

    # Sums
    @total = { }
    unless @timesheet.sort == :issue
      @timesheet.time_entries.each do |project,logs|
        @total[project] = 0
        if logs[:logs]
          logs[:logs].each do |log|
            @total[project] += log.hours
          end
        end
      end
    else
      @timesheet.time_entries.each do |project, project_data|
        @total[project] = 0
        if project_data[:issues]
          project_data[:issues].each do |issue, issue_data|
            @total[project] += issue_data.collect(&:hours).sum
          end
        end
      end
    end

    @grand_total = @total.collect{|k,v| v}.inject{|sum,n| sum + n}

    respond_to do |format|
      format.html { render :action => 'details', :layout => false if request.xhr? }
      format.csv  { send_data @timesheet.to_csv, :filename => 'timesheet.csv', :type => "text/csv" }
    end
  end

  def context_menu
    @time_entries = TimeEntry.where(['id IN (?)', params[:ids]])
    render :layout => false
  end

  def reset
    clear_filters_from_session
    redirect_to :action => 'index'
  end

  private
  def get_list_size
    @list_size = Setting.plugin_redmine_timesheet_plugin['list_size'].to_i
  end

  def get_precision
    precision = Setting.plugin_redmine_timesheet_plugin['precision']

    if precision.blank?
      # Set precision to a high number
      @precision = 10
    else
      @precision = precision.to_i
    end
  end

  def get_activities
    @activities = TimeEntryActivity.where('parent_id IS NULL')
  end

  def allowed_projects
    if User.current.admin?
      return Project.order('name ASC')
    else
      return Project.where(Project.visible_condition(User.current)).order('name ASC')
    end
  end

  def clear_filters_from_session
    session[SessionKey] = nil
  end

  def load_filters_from_session
    if session[SessionKey]
      @timesheet = Timesheet.new(session[SessionKey])
      @timesheet.period_type = Timesheet::ValidPeriodType[:default]
    end

    if session[SessionKey] && session[SessionKey]['projects']
      @timesheet.projects = allowed_projects.find_all { |project|
        session[SessionKey]['projects'].include?(project.id.to_s)
      }
    end
  end

  def save_filters_to_session(timesheet)
    if params[:timesheet]
      # Check that the params will fit in the session before saving
      # prevents an ActionController::Session::CookieStore::CookieOverflow
      encoded = Base64.encode64(Marshal.dump(params[:timesheet]))
      if encoded.size < 2.kilobytes # Only use 2K of the cookie
        session[SessionKey] = params[:timesheet]
      end
    end

    if timesheet
      session[SessionKey] ||= {}
      session[SessionKey]['date_from'] = timesheet.date_from
      session[SessionKey]['date_to'] = timesheet.date_to
    end
  end

end
