class Streamlined::Column::ActiveRecord < Streamlined::Column::Base
  attr_accessor :ar_column, :enumeration, :check_box
  attr_with_default :filterable, 'true'
  delegates :name, :to => :ar_column
  delegates :table_name, :to => :parent_model
  
  def initialize(ar_column, parent_model)
    @ar_column = ar_column
    @human_name = ar_column.human_name if ar_column.respond_to?(:human_name)
    @parent_model = parent_model
  end
  
  def active_record?
    true
  end
  
  def filterable?
    filterable
  end
  
  def filter_column
    name
  end
  
  def ==(o)
    return true if o.object_id == object_id
    return false unless self.class == o.class
    return self.ar_column == o.ar_column &&
           self.human_name == o.human_name &&
           self.enumeration == o.enumeration
  end
  
  def edit_view
    Streamlined::View::EditViews.create_relationship(:enumerable_select)
  end
  
  def render_td_show(view, item)
    if enumeration
      content = item.send(self.name)
      content = content && !content.blank? ? content : self.unassigned_value
      content = wrap_with_link(content, view, item)
    else
      render_content(view, item)
    end
  end
  
  def render_td_list(view, item)
    id = relationship_div_id(name, item)
    div = render_td_show(view, item)
    div = div_wrapper(id) { div } if enumeration
    div += view.link_to_function("Edit", "Streamlined.Enumerations." <<
      "open_enumeration('#{id}', this, '/#{view.controller_name}')") if enumeration && editable
    div
  end
  
  # helper method to let us apply Streamlined global edit_format_for hook
  def custom_column_value(view, model_underscore, method_name)                   
    model_instance = view.instance_variable_get("@#{model_underscore}")                                                                     
    value = unless model_instance.nil?
      model_instance.send(method_name)
    end
    modified_value = Streamlined.format_for_edit(value)
    value == modified_value ? nil : modified_value
  end
  
  # TODO: This method depends on item being in scope under the instance variable name
  #       :@#model_underscore. Yucky, but Rails' input method expects this. Revisit.
  def render_td_edit(view, item)
    if enumeration
      result = render_enumeration_select(view, item)
    elsif check_box
      result = view.check_box(model_underscore, name, html_options)
    else                                           
      custom_value = custom_column_value(view, model_underscore, name)   
      options = custom_value ? html_options.merge(:value => custom_value) : html_options
      result = view.input(model_underscore, name, options)
    end
    wrap(result)
  end
  alias :render_td_new :render_td_edit
  
  def render_enumeration_select(view, item)
    id = relationship_div_id(name, item)
    choices = enumeration.to_2d_array
    choices.unshift(unassigned_option) if column_can_be_unassigned?(parent_model, name.to_sym)
    args = [model_underscore, name, choices]
    args << {} << html_options unless html_options.empty?
    view.select(*args)
  end
end