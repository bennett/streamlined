require File.join(File.dirname(__FILE__), '../../test_functional_helper')
require 'streamlined/reflection'

class Streamlined::UIFunctionalTest < Test::Unit::TestCase
  def setup
    Streamlined::ReloadableRegistry.reset
    @poet_ui = Streamlined.ui_for(Poet)
    @poem_ui = Streamlined.ui_for(Poem) do
      list_columns :text,
                   :text_with_div,
                   :poet, { :filter_column => "first_name" }
    end
  end
  
  def test_all_columns
    assert_equal_sets([:id,:first_name,:poems,:last_name],@poet_ui.all_columns.map{|x| x.name.to_sym})
  end

  def test_default_user_columns
    assert_equal_sets([:first_name,:poems,:last_name],@poet_ui.user_columns.map{|x| x.name.to_sym})
  end
  
  def test_user_columns_act_as_template_for_other_column_groups
    @poet_ui.user_columns :first_name, {:read_only => true}, :last_name
    @poet_ui.list_columns :first_name, :last_name, {:read_only => true}
    assert_equal true, @poet_ui.scalars[:first_name].read_only, "settings shared from user_columns"
    assert_equal false, @poet_ui.scalars[:last_name].read_only, "settings not share from other column groups"
  end
  
  def test_view_specific_columns
    @poet_ui.user_columns :first_name, :last_name
    assert_equal false, @poet_ui.scalars[:first_name].read_only
    assert_equal false, @poet_ui.scalars[:last_name].read_only
    assert_same @poet_ui.show_columns, @poet_ui.user_columns
    @poet_ui.show_columns :first_name, {:read_only=>true}, :last_name, {:read_only=>true}
    assert_not_same @poet_ui.show_columns, @poet_ui.user_columns
    assert_equal true, @poet_ui.show_columns.first.read_only
    assert_equal true, @poet_ui.show_columns.last.read_only
  end
  
  # this allows us to declare ui options for dynamic methods not added yet
  def test_can_find_instance_method_when_not_declared
    assert_nothing_raised {@poet_ui.list_columns :first_name, :last_name, :nonexistent_method}
    assert_equal 3, @poet_ui.list_columns.length
  end

  def test_id_fragment
    assert_equal "Count", @poet_ui.id_fragment(Poet.reflect_on_association(:poems), "show")
    assert_equal "Membership", @poet_ui.id_fragment(Poet.reflect_on_association(:poems), "edit")
  end      
  
  def test_reflect_on_model_with_no_delegates
    assert_equal({}, @poet_ui.reflect_on_delegates)
  end
              
  # TODO: hash storage of name/column pairs will result in name collisions if 
  # two different delegates have the same column names. Is this intentional?
  def test_reflect_on_model_with_delegates
    @poet_ui.model = Authorship
    delegate_hash = @poet_ui.reflect_on_delegates
    assert_key_set [:articles, :first_name, :full_name, :authorships, :id, :books, :last_name], delegate_hash
    assert_equal_sets [Streamlined::Column::Addition, Streamlined::Column::Association, Streamlined::Column::ActiveRecord], delegate_hash.values.map(&:class)
  end
  
  def test_conditions_by_like_with_associations
    ui = Streamlined.ui_for(Poet) do
      list_columns :first_name, :last_name, :poems, { :filter_column => :text }
    end
    expected = "poets.first_name LIKE '%value%' OR poets.last_name LIKE '%value%' OR poems.text LIKE '%value%'"
    assert_equal expected, ui.conditions_by_like_with_associations("value")
  end

  def test_conditions_by_like_with_associations_for_unconventional_table_names
    expected = "people.first_name LIKE '%value%' OR people.last_name LIKE '%value%'"
    assert_equal expected, Streamlined.ui_for(Unconventional).conditions_by_like_with_associations("value")
  end
  
  def test_conditions_by_like_with_non_filterable_columns
    expected = "people.first_name LIKE '%value%'"
    ui = Streamlined.ui_for(Person) { user_columns :first_name, :last_name, { :filterable => false }}
    assert_equal expected, ui.conditions_by_like_with_associations("value")
  end
  
  def test_conditions_by_like_uses_list_columns
    ui = Streamlined.ui_for(Person) do
      user_columns :first_name
      list_columns :first_name, :last_name
    end
    expected = "people.first_name LIKE '%value%' OR people.last_name LIKE '%value%'"
    assert_equal expected, ui.conditions_by_like_with_associations("value")
  end
  
  def test_columns_not_aliased_between_scalars_and_delegates
    assert_not_nil(poem_first_name = @poem_ui.column(:first_name))
    assert_not_nil(poet_first_name = @poet_ui.column(:first_name))
  end
  
  def test_columns_not_aliased_between_column_groups
    template_column = @poet_ui.column(:first_name)
    list_column = @poet_ui.column(:first_name, :crud_context => :list)
    show_column = @poet_ui.column(:first_name, :crud_context => :show)
    assert_not_nil template_column
    assert_same template_column, list_column, "column groups share template until they are set"
    assert_same show_column, list_column, "column groups share template until they are set"
    @poet_ui.show_columns :first_name, :last_name
    assert_not_same show_column, @poet_ui.column(:first_name, :crud_context => :show), 
                    "show_columns should get its own copy of first_name"
    assert_same list_column, @poet_ui.column(:first_name, :crud_context => :list),
                    "list_columns should not be affected by setting show_columns"
    assert_same template_column, @poet_ui.column(:first_name),
                    "template columns should not be affected by setting show_columns"
  end

  def setup_export_tests
    stock_controller_and_view
    @all_export_formats = [:enhanced_xml_file, :xml_stylesheet, :enhanced_xml, :xml, :csv, :json, :yaml]
    @columns_to_export_formats = [:enhanced_xml, :enhanced_xml_file, :xml_stylesheet]
  end

  def test_all_export_links_are_present_by_default
    setup_export_tests
    export_links = @all_export_formats
    assert_equal export_links, @view.send(:model_ui).exporters
    export_links.each {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format))}    
  end                                                                                                                                                              

  def test_declarative_exporters_none                                                                                                                              
    setup_export_tests
    export_links = @all_export_formats
    @view.send(:model_ui).exporters :none                                                                                                                          
    # Need to get the response again with the new model_ui settings
    get 'index'
    assert_equal :none, @view.send(:model_ui).exporters
    export_links.each {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format), false)}
    
    # Also make sure there is no export link on the page
    look_for   = "div[id=controls] a[href=#][onclick=\"Element.toggle('show_export'); return false;\"]"
    count = 0
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end                                                                                                                                                              
                                                                                                                                                                   
  def test_declarative_exporters_all                                                                                                                               
    setup_export_tests
    export_links = @all_export_formats
    @view.send(:model_ui).exporters export_links
    get 'index'
    assert_equal export_links, @view.send(:model_ui).exporters
    export_links.each {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format))}    
  end                                                                                                                                                              

  def test_declarative_exporters_one
    setup_export_tests
    one_format = :yaml
    other_export_links = @all_export_formats - Array(one_format)
    @view.send(:model_ui).exporters one_format
    get 'index'
    assert_equal one_format, @view.send(:model_ui).exporters
    assert_export_link(one_format, @view.send(:model_ui).default_exporter?(one_format))
    other_export_links.each {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format), false)}
  end

  def test_declarative_exporters_several
    setup_export_tests
    several_formats = :csv, :xml
    other_export_links = @all_export_formats - several_formats
    @view.send(:model_ui).exporters several_formats
    get 'index'
    assert_equal several_formats, @view.send(:model_ui).exporters
    several_formats.each    {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format))}
    other_export_links.each {|format| assert_export_link(format, @view.send(:model_ui).default_exporter?(format), false)}
  end

  def test_export_defaults
    setup_export_tests
    assert_equal true, @view.send(:model_ui).allow_full_download
    assert_equal true, @view.send(:model_ui).default_full_download
    assert_equal ',',  @view.send(:model_ui).default_separator
    assert_equal nil,  @view.send(:model_ui).default_skip_header
    assert_equal :enhanced_xml_file, @view.send(:model_ui).default_exporter
    assert_equal [],   @view.send(:model_ui).default_deselected_columns
  end

  def test_allow_full_download_true_and_default_full_download_true
    setup_export_tests
    @view.send(:model_ui).allow_full_download   true
    @view.send(:model_ui).default_full_download true
    get 'index'
    assert_equal true, @view.send(:model_ui).allow_full_download
    assert_equal true, @view.send(:model_ui).default_full_download
    assert_full_download(false, !@view.send(:model_ui).default_full_download)  
    assert_full_download(true,   @view.send(:model_ui).default_full_download)  
  end

  def test_allow_full_download_true_and_default_full_download_false
    setup_export_tests
    @view.send(:model_ui).allow_full_download   true
    @view.send(:model_ui).default_full_download false
    get 'index'
    assert_equal true, @view.send(:model_ui).allow_full_download
    assert_equal false, @view.send(:model_ui).default_full_download
    assert_full_download(false, !@view.send(:model_ui).default_full_download)  
    assert_full_download(true,   @view.send(:model_ui).default_full_download)  
  end

  def test_not_visible_when_allow_full_download_false
    setup_export_tests
    @view.send(:model_ui).allow_full_download   false
    @view.send(:model_ui).default_full_download true
    get 'index'
    assert_equal false, @view.send(:model_ui).allow_full_download
    assert_equal true, @view.send(:model_ui).default_full_download
    assert_full_download(false, !@view.send(:model_ui).default_full_download, false)  
    assert_full_download(true,   @view.send(:model_ui).default_full_download, false)  
  end

  def test_default_separator
    setup_export_tests
    separator = ';'
    @view.send(:model_ui).default_separator separator
    get 'index'
    assert_equal separator, @view.send(:model_ui).default_separator
    look_for = "div[id=show_export] form[id=export] p label input[id=separator][type=text][value=#{separator}][name=separator][size=1][maxlength=1]"
    count = 1
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end

  def test_default_separator_visible_for_csv
    setup_export_tests
    separator = ','
    @view.send(:model_ui).exporters :csv
    get 'index'
    assert_equal :csv, @view.send(:model_ui).exporters
    look_for = "div[id=show_export] form[id=export] p label input[id=separator][type=text][value=#{separator}][name=separator][size=1][maxlength=1]"
    count = 1
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end

  def test_default_separator_not_visible_for_other_formats
    setup_export_tests
    separator = ','
    formats = @all_export_formats - Array(:csv)
    @view.send(:model_ui).exporters formats
    get 'index'
    assert_equal formats, @view.send(:model_ui).exporters
    look_for = "div[id=show_export] form[id=export] p label input[id=separator][type=text][value=#{separator}][name=separator][size=1][maxlength=1]"
    count = 0
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end

  def test_default_skip_header_true
    skip_header_setup(true)
    assert_default_skip_header(true)
  end

  def test_default_skip_header_false
    skip_header_setup(false)
    assert_default_skip_header(false)
    # and confirm its not showing up as checked
    assert_default_skip_header(true, false)
  end

  def test_skip_header_visible_for_csv
    setup_export_tests
    @view.send(:model_ui).exporters :csv
    get 'index'
    assert_equal :csv, @view.send(:model_ui).exporters
    assert_default_skip_header(false)
  end

  def test_skip_header_not_visible_for_other_formats
    setup_export_tests
    formats = @all_export_formats - Array(:csv)
    @view.send(:model_ui).exporters formats
    get 'index'
    assert_equal formats, @view.send(:model_ui).exporters
    assert_default_skip_header(false, false)
  end

  def test_default_deselected_columns_with_symbol
    setup_export_tests
    column = :last_name
    @view.send(:model_ui).default_deselected_columns column
    get 'index'
    assert_equal column, @view.send(:model_ui).default_deselected_columns
    selected = false
    assert_selected_column(column, selected)

    # and confirm its not showing up as checked
    selected = true
    assert_selected_column(column, selected, false)

    other_columns = :first_name, :full_name
    selected = true
    other_columns.each {|column| assert_selected_column(column, selected)}
  end

  def test_default_deselected_columns_with_array
    setup_export_tests
    columns = :first_name, :full_name
    @view.send(:model_ui).default_deselected_columns columns
    get 'index'
    assert_equal columns, @view.send(:model_ui).default_deselected_columns
    selected = false
    columns.each {|column| assert_selected_column(column, selected)}
    # and confirm they're not showing up as checked
    selected = true
    columns.each {|column| assert_selected_column(column, selected, false)}

    other_column = :last_name
    selected = true
    assert_selected_column(other_column, selected)
  end
  
  def test_columns_to_export_not_visible_for_other_formats
    setup_export_tests
    formats = @all_export_formats - @columns_to_export_formats
    @view.send(:model_ui).exporters formats
    get 'index'
    assert_equal formats, @view.send(:model_ui).exporters
    
    columns = :first_name, :last_name, :full_name
    selected = false
    columns.each {|column| assert_selected_column(column, selected, false)}
  end

  def test_columns_to_export_header_visible
    setup_export_tests
    formats = @columns_to_export_formats
    look_for = "div[id=show_export] form[id=export] h4"
    count = 1
    text="Columns to export&nbsp;&nbsp;(Enhanced XML and XML Stylesheet)"
    formats.each do |format|
      @view.send(:model_ui).exporters format
      get 'index'
      assert_equal format, @view.send(:model_ui).exporters
      error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} for format=#{format} in @response.body"
      assert_select look_for, {:count => count, :text => text}, error_msg
    end
    # and check all formats together
    @view.send(:model_ui).exporters @all_export_formats
    get 'index'
    assert_equal @all_export_formats, @view.send(:model_ui).exporters
    error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} for format=#{@all_export_formats} in @response.body"
    assert_select look_for, {:count => count, :text => text}, error_msg
  end

  def test_columns_to_export_header_not_visible
    setup_export_tests
    formats = @all_export_formats - @columns_to_export_formats
    look_for = "div[id=show_export] form[id=export] h4"
    count = 0
    text="Columns to export&nbsp;&nbsp;(Enhanced XML and XML Stylesheet)"
    formats.each do |format|
      @view.send(:model_ui).exporters format
      get 'index'
      assert_equal format, @view.send(:model_ui).exporters
      error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} for format=#{format} in @response.body"
      assert_select look_for, {:count => count, :text => text}, error_msg
    end
    # and check all formats together
    @view.send(:model_ui).exporters formats
    get 'index'
    assert_equal formats, @view.send(:model_ui).exporters
    error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} for format=#{formats} in @response.body"
    assert_select look_for, {:count => count, :text => text}, error_msg
  end

  def test_options_header_visible_for_csv
    setup_export_tests
    @view.send(:model_ui).exporters :csv
    get 'index'
    assert_equal :csv, @view.send(:model_ui).exporters
    look_for = "div[id=show_export] form[id=export] h4"
    count = 1
    text="Options"
    error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} in @response.body"
    assert_select look_for, {:count => count, :text => text}, error_msg
  end

  def test_options_header_visible_for_allow_full_download
    setup_export_tests
    @view.send(:model_ui).allow_full_download true
    get 'index'
    assert_equal true, @view.send(:model_ui).allow_full_download
    look_for = "div[id=show_export] form[id=export] h4"
    count = 1
    text="Options"
    error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} in @response.body"
    assert_select look_for, {:count => count, :text => text}, error_msg
  end

  def test_options_header_not_visible_when_no_options
    setup_export_tests
    @view.send(:model_ui).allow_full_download false
    @view.send(:model_ui).exporters :xml
    get 'index'
    assert_equal false, @view.send(:model_ui).allow_full_download
    assert_equal :xml, @view.send(:model_ui).exporters
    look_for = "div[id=show_export] form[id=export] h4"
    count = 0
    text="Options"
    error_msg = "Did not find #{look_for} with count=#{count} and text=#{text} in @response.body"
    assert_select look_for, {:count => count, :text => text}, error_msg
  end

  def test_the_default_exporter_is_checked 
    setup_export_tests
    default = @view.send(:model_ui).default_exporter
    other_export_links = @all_export_formats - Array(default)
    assert_equal true, @view.send(:model_ui).default_exporter?(default)
    assert_export_link(default, true)
    # and check that the others are there
    other_export_links.each {|format| assert_export_link(format, false)}    
    # but that we do not find them there as checked
    other_export_links.each {|format| assert_export_link(format, true, false)}    
  end

  def test_default_exporter_with_one_exporter
    setup_export_tests
    exporter = :csv
    @view.send(:model_ui).exporters exporter
    get 'index'
    assert_equal true, @view.send(:model_ui).default_exporter?(exporter)
    assert_equal exporter, @view.send(:model_ui).exporters
    other_export_links = @all_export_formats - Array(exporter)
    assert_export_link(exporter, true)
    # and check that the others are not there
    other_export_links.each {|format| assert_export_link(format, false, false)}    
  end

  def test_default_exporter_with_several_including_default
    setup_export_tests
    default = @view.send(:model_ui).default_exporter
    exporters = :yaml, default, :json
    @view.send(:model_ui).exporters exporters
    get 'index'
    assert_true @view.send(:model_ui).default_exporter?(default)
    assert_equal exporters, @view.send(:model_ui).exporters
    other_export_links = exporters - Array(default)
    assert_export_link(default, true)
    # and check that the others are there
    other_export_links.each {|format| assert_export_link(format, false)}    
    # but that we do not find them there as checked
    other_export_links.each {|format| assert_export_link(format, true, false)}    
  end

  def test_default_exporter_with_several_excluding_default
    setup_export_tests
    exporters = :xml, :yaml, :json
    default = exporters.first
    @view.send(:model_ui).exporters exporters
    get 'index'
    assert_true @view.send(:model_ui).default_exporter?(default)
    assert_equal exporters, @view.send(:model_ui).exporters
    other_export_links = exporters - Array(default)
    assert_export_link(default, true)
    # and check that the others are there
    other_export_links.each {|format| assert_export_link(format, false)}    
    # but that we do not find them there as checked
    other_export_links.each {|format| assert_export_link(format, true, false)}    
  end

private

  def assert_export_link(format, check, should_be_present = true)
    link_text = {:csv => :csv, :xml => :xml, :json => :json, :yaml => :yaml, :enhanced_xml_file => :EnhancedXMLToFile, :xml_stylesheet => :XMLStylesheet ,:enhanced_xml => :EnhancedXML }[format]
    checked = check ? "[checked=checked]" : ""
    assert_select "div[id=show_export] form[id=export] p label input[id=format_#{link_text.to_s.downcase}][type=radio][value=#{link_text}][name=format]#{checked}", :count => should_be_present ? 1 : 0
  end 

  def assert_full_download(name, check, should_be_present = true)
    checked = check == true ? "[checked=checked]" : ""
    assert_select "div[id=show_export] form[id=export] p label input[id=full_download_#{name}][type=radio][value=#{name}][name=full_download]#{checked}", :count => should_be_present ? 1 : 0  
  end

  def assert_default_skip_header(flag, should_be_present = true)
    checked = flag == true ? "[checked=checked]" : ""
    look_for = "div[id=show_export] form[id=export] p label input[id=skip_header][type=checkbox][value=1][name=skip_header]#{checked}"
    count = should_be_present ? 1 : 0
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end
  
  def assert_selected_column(name, selected, should_be_present = true)
    checked = selected == true ? "[checked=checked]" : ""
    look_for = "div[id=show_export] form[id=export] p label input[id*=export_columns][id*=#{name}][type=checkbox][value=1][name*=export_columns][name*=#{name}]#{checked}"
    count = should_be_present ? 1 : 0
    error_msg = "Did not find #{look_for} with count=#{count} in @response.body"
    assert_select look_for, {:count => count}, error_msg
  end

  def skip_header_setup(flag)
    setup_export_tests
    @view.send(:model_ui).default_skip_header flag
    get 'index'
    assert_equal flag, @view.send(:model_ui).default_skip_header
  end

end
