class Admin::ResourcesController < Admin::BaseController

  include Typus::Controller::Actions
  include Typus::Controller::ActsAs
  include Typus::Controller::Associations
  include Typus::Controller::Autocomplete
  include Typus::Controller::Filters
  include Typus::Controller::Format

  Whitelist = [:edit, :update, :destroy, :toggle, :position, :relate, :unrelate]

  before_filter :get_model
  before_filter :set_context # MultiSite ...
  before_filter :get_object, :only => Whitelist + [:show]
  before_filter :check_resource_ownership, :only => Whitelist
  before_filter :check_if_user_can_perform_action_on_resources

  ##
  # This is the main index of the model. With filters, conditions and more.
  #
  # By default application can respond to html, csv and xml, but you can add
  # your formats.
  #
  def index
    get_objects

    respond_to do |format|
      format.html do
        add_resource_action(default_action.titleize, {:action => default_action}, {})
        add_resource_action("Trash", {:action => "destroy"}, {:confirm => "#{Typus::I18n.t("Trash")}?", :method => 'delete'})
        generate_html
      end
      @resource.typus_export_formats.each { |f| format.send(f) { send("generate_#{f}") } }
    end
  end

  def new
    item_params = params.dup
    item_params.delete_if { |k, v| !@resource.columns.map(&:name).include?(k) }
    @item = @resource.new(item_params)

    respond_to do |format|
      format.html # new.html.erb
      format.json { render :json => @item }
    end
  end

  ##
  # Create new items. There's an special case when we create an item from
  # another item. In this case, after the item is created we also create the
  # relationship between these items.
  #
  def create
    @item = @resource.new(params[@object_name])

    set_attributes_on_create

    respond_to do |format|
      if @item.save
        format.html do
          params[:resource] ? create_with_back_to : redirect_on_success
        end
        format.json { render :json => @item, :status => :created, :location => @item }
      else
        format.html { render :action => "new" }
        format.json { render :json => @item.errors, :status => :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def show
    check_resource_ownership if @resource.typus_options_for(:only_user_items)

=begin
    # FIXME
    respond_to do |format|
      format.html # show.html.erb
      format.json { render :json => @item }
    end
=end
  end

  def update
    attributes = params[:attribute] ? { params[:attribute] => nil } : params[@object_name]

    respond_to do |format|
      if @item.update_attributes(attributes)
        set_attributes_on_update
        format.html { redirect_on_success }
        format.json { render :json => @item }
      else
        format.html { render :edit }
        format.json { render :json => @item.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    if @item.destroy
      notice = Typus::I18n.t("%{model} successfully removed.", :model => @resource.model_name.human)
    else
      alert = @item.errors.full_messages
    end
    redirect_to :back, :notice => notice, :alert => alert
  end

  def toggle
    @item.toggle(params[:field])

    respond_to do |format|
      if @item.save
        format.html do
          notice = Typus::I18n.t("%{model} successfully updated.", :model => @resource.model_name.human)
          redirect_to :back, :notice => notice
        end
        format.json { render :json => @item }
      else
        format.html { render :edit }
        format.json { render :json => @item.errors, :status => :unprocessable_entity }
      end
    end
  end

  private

  def get_model
    @resource = params[:controller].extract_class
    @object_name = ActiveModel::Naming.singular(@resource)
  end

  def resource
    params[:controller].extract_class
  end
  helper_method :resource

  def set_context
    @resource
  end
  helper_method :set_context

  def get_object
    @item = @resource.find(params[:id])
  end

  def get_objects
    eager_loading = @resource.reflect_on_all_associations(:belongs_to).reject { |i| i.options[:polymorphic] }.map { |i| i.name }

    @resource.build_conditions(params).each do |condition|
      @resource = @resource.where(condition)
    end

    @resource.build_joins(params).each do |join|
      @resource = @resource.joins(join)
    end

    if @resource.typus_options_for(:only_user_items)
      check_resources_ownership
    end

    @resource = @resource.order(set_order).includes(eager_loading)
  end

  def fields
    @resource.typus_fields_for(params[:action])
  end
  helper_method :fields

  def set_order
    params[:sort_order] ||= "desc"
    params[:order_by] ? "#{@resource.table_name}.#{params[:order_by]} #{params[:sort_order]}" : @resource.typus_order_by
  end

  def redirect_on_success
    path = params.dup.cleanup

    if action_after_save.eql?('index')
      path.delete_if { |k, v| %w(action id).include?(k) }
    else
      path.merge!(:action => action_after_save, :id => @item.id)
    end

    message = (params[:action] == 'create') ? "%{model} successfully created." : "%{model} successfully updated."
    notice = Typus::I18n.t(message, :model => @resource.model_name.human)

    redirect_to path, :notice => notice
  end

  ##
  # Here what we basically do is to associate objects after they have been
  # created. It's similar to calling `relate` but which the difference that
  # we are creating a new record.
  #
  # We have two objects, detect the relationship_between them and then
  # call the related method.
  #
  def create_with_back_to
    item_class = params[:resource].typus_constantize
    # For some reason we are forced to set the /admin prefix to the controller
    # when working with namespaced stuff.
    options = { :controller => "/admin/#{item_class.to_resource}" }
    assoc = item_class.relationship_with(@resource).to_s
    send("set_#{assoc}_association", item_class, options)
  end

  def default_action
    @resource.typus_options_for(:default_action_on_item)
  end

  def action_after_save
    @resource.typus_options_for(:action_after_save)
  end

end
