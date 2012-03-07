module Kameleon
  module DSL
    module Verify
      class Presence

        attr_accessor :conditions, :params

        def initialize(*params)
          @params = params
          @conditions = []

          parse_conditions
        end

        private

        def parse_conditions
          prepare_conditions(params)
        end

        def prepare_conditions(param)
          case param
            when String
              conditions << Condition.new(:have_content, param)
            when Hash
              param.each_pair do |type, values|
                case type
                  when :link, :links
                    conditions.concat Link.new(values).conditions
                  when :image, :images
                    conditions.concat Image.new(values).conditions
                  when :ordered
                    conditions.concat Sequence.new(values).conditions
                  when Fixnum
                    conditions.concat Quantity.new(type, values).conditions
                  when String
                    conditions.concat TextInput.new(type, values).conditions
                  when :checked, :unchecked, :check, :uncheck
                    conditions.concat CheckBoxInput.new(type, values).conditions
                  when :selected, :unselected, :select, :unselect
                    conditions.concat SelectInput.new(type, values).conditions
                  when :field, :fields
                    conditions.concat TextInput.new(nil, values).conditions
                  when :empty
                    conditions.concat EmptyInput.new(values).conditions
                  else
                    raise "not implemented"
                end
              end
            when Array
              params.each { |parameter| prepare_conditions(parameter) }
            else
              raise "not implemented"
          end
        end
      end

      class Condition
        attr_accessor :method, :params, :block

        def initialize(method, *params, &block)
          @method = method
          @params = params
          @block = block
        end
      end

      class Link
        attr_reader :conditions

        def initialize(params)
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when Hash
              params.each_pair do |text, url|
                conditions << Condition.new(:have_link, text, :href => url)
              end
            when String
              conditions << Condition.new(:have_link, params)
            when Array
              params.each { |param| parse_params(param) }
            else
              raise 'not implemented'
          end
        end
      end

      class Image
        attr_reader :conditions

        def initialize(params)
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when String
              conditions << Condition.new(:have_xpath, prepare_xpath(params))
            when Array
              params.each { |param| parse_params(param) }
            else
              raise 'not implemented'
          end
        end

        def prepare_xpath(alt_or_src)
          "//img[@alt=\"#{alt_or_src}\"] | //img[@src=\"#{alt_or_src}\"]"
        end
      end

      class Quantity
        attr_reader :conditions
        attr_reader :quantity

        def initialize(quantity, params)
          @conditions = []
          @quantity = quantity
          parse_params(params)
        end

        private

        def parse_params(params)
          if params === Array && params.first == Array
            params.each { |param| parse_params(param) }
          else
            #! refactor
            selector = prepare_query(params).selector
            conditions << Condition.new(prepare_method(selector), selector.last, :count => quantity)
          end
        end

        def prepare_query(selector)
          Context::Scope.new(selector)
        end

        #! refactor - delagate to Context::Scope class
        def prepare_method(query)
          query.first == :xpath ?
              :have_xpath :
              :have_css
        end
      end

      class Sequence
        attr_reader :params

        def initialize(params)
          @params = params
        end


        def conditions
          [condition]
        end

        private

        def condition
          Condition.new(nil, params, prepare_xpath) do |elements, xpath_query|
            texts = page.all(:xpath, xpath_query).map(&:text)
            texts.should == elements
          end
        end

        def prepare_xpath
          params.collect { |n| "//node()[text()= \"#{n}\"]" }.join(' | ')
        end
      end

      class TextInput
        attr_reader :conditions, :value

        def initialize(value, *params)
          @value = value
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when String
              conditions << Condition.new(:have_field, params, :with => value)
            when Array
              params.each { |param| parse_params(param) }
            else
              raise "not supported"
          end
        end
      end


      class EmptyInput
        attr_reader :conditions

        def initialize(*params)
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when String
              conditions << condition(params)
            when Array
              params.each { |param| parse_params(param) }
            else
              raise "not supported"
          end
        end

        def condition(params)
          Condition.new(nil, params) do |element|
            page.should have_field(element)
            find_field(element).value.should satisfy do |value|
              value == nil or value == ""
            end
          end
        end
      end

      class CheckBoxInput
        attr_reader :conditions, :value

        def initialize(value, *params)
          @value = value
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when String
              conditions << Condition.new(matcher_method, params)
            when Array
              params.each { |param| parse_params(param) }
            else
              raise "not supported"
          end
        end

        def matcher_method
          case value
            when :checked, :check
              :have_checked_field
            when :unchecked, :uncheck
              :have_unchecked_field
            else
              raise "not supported"
          end
        end
      end

      class SelectInput
        attr_reader :conditions, :value

        def initialize(value, *params)
          @value = value
          @conditions = []
          parse_params(params)
        end

        private

        def parse_params(params)
          case params
            when Hash
              params.each_pair do |selected_value, identifier|
                case identifier
                  when Array
                    selected_value.each do |value|
                      parse_params(value => identifier)
                    end
                  when String
                    conditions << Condition.new(matcher_method, identifier, :selected => selected_value)
                  else
                    raise "not supported"
                end
              end
            when Array
              params.each { |param| parse_params(param) }
            else
              raise "not supported"
          end
        end


        def matcher_method
          case value
            when :selected, :select
              :have_select
            when :unselected, :unselect
              :have_no_select
            else
              raise "not supported"
          end
        end
      end

    end

  end
end

#    when 'Hash'
#      options.each_pair do |value, locator|
#        case value.class.name
#          when 'Symbol'
#            case value
#              when :button, :buttons
#                one_or_all(locator).each do |selector|
#                  session.should rspec_world.have_button(selector)
#                end
#              when :disabled, :readonly
#                one_or_all(locator).each do |selector|
#                  see :field => selector
#                  case session.driver
#                    when Capybara::Selenium::Driver
#                      session.find_field(selector)[value].should == 'true'
#                    when Capybara::RackTest::Driver
#                      session.find_field(selector)[value].should ==(value.to_s)
#                  end
#                end
#              when :error_message_for, :error_messages_for
#                one_or_all(locator).each do |selector|
#                  session.find(:xpath, '//div[@id="error_explanation"]').should rspec_world.have_content(selector.capitalize)
#                end