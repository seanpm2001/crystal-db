require "spec"

private def assert_single_read(rs, value_type, value)
  rs.move_next.should be_true
  rs.read(value_type).should eq(value)
  rs.move_next.should be_false
end

module DB
  class DriverSpecs(DBAnyType)

    record ColumnDef, name : String, sql_type : String, null : Bool

    @before : Proc(Nil) = ->{}
    @after : Proc(Nil) = ->{}
    @encode_null = "NULL"

    def before(&@before : -> Nil)
    end

    def after(&@after : -> Nil)
    end

    def encode_null(@encode_null : String)
    end

    # :nodoc:
    macro db_spec_config(name, *, block = false)
      {% if name.is_a?(TypeDeclaration) %}
        @{{name.var.id}} : {{name.type}}?

        {% if block %}
          def {{name.var.id}}(&@{{name.var.id}} : {{name.type}})
          end
        {% else %}
          def {{name.var.id}}(@{{name.var.id}} : {{name.type}})
          end
        {% end %}

        # :nodoc:
        def {{name.var.id}}
          res = @{{name.var.id}}
          raise %{Missing {{name.var.id}} to setup db} unless res
          res
        end
      {% end %}
    end

    db_spec_config connection_string : String
    db_spec_config binding_syntax : Proc(Int32, String), block: true
    db_spec_config select_scalar_syntax : Proc(String, String), block: true
    db_spec_config create_table_1column_syntax : Proc(String, ColumnDef, String), block: true
    db_spec_config create_table_2columns_syntax : Proc(String, ColumnDef, ColumnDef, String), block: true
    db_spec_config insert_1column_syntax : Proc(String, String, String, String), block: true
    db_spec_config insert_2columns_syntax : Proc(String, String, String, String, String, String), block: true
    db_spec_config select_1column_syntax : Proc(String, String, String), block: true
    db_spec_config select_2columns_syntax : Proc(String, String, String, String), block: true
    db_spec_config select_count_syntax : Proc(String, String), block: true

    record SpecIt, description : String, prepared : Symbol, file : String, line : Int32, end_line : Int32, block : DB::Database -> Nil
    getter its = [] of SpecIt

    def it(description = "assert", prepared = :default, file = __FILE__, line = __LINE__, end_line = __END_LINE__, &block : DB::Database ->)
      return unless Spec.matches?(description, file, line, end_line)
      @its << SpecIt.new(description, prepared, file, line, end_line, block)
    end

    record ValueDef(T), value : T, sql_type : String, value_encoded : String

    @values = [] of ValueDef(DBAnyType)
    def sample_value(value, sql_type, value_encoded, *, type_safe_value = true)
      @values << ValueDef(DBAnyType).new(value, sql_type, value_encoded)

      it "select nil as (#{typeof(value)} | Nil)", prepared: :both do |db|
        db.query select_scalar(encode_null) do |rs|
          assert_single_read rs, typeof(value || nil), nil
        end
      end

      value_desc = value.to_s
      value_desc = "#{value_desc[0..20]}...(#{value_desc.size})" if value_desc.size > 20
      value_desc = "#{value_desc} as #{sql_type}"

      if type_safe_value
        it "executes with bind #{value_desc}" do |db|
          db.scalar(select_scalar(param(1)), value).should eq(value)
        end

        it "executes with bind #{value_desc} as array" do |db|
          db.scalar(select_scalar(param(1)), [value]).should eq(value)
        end

        it "select #{value_desc} as literal" do |db|
          db.scalar(select_scalar(value_encoded)).should eq(value)

          db.query select_scalar(value_encoded) do |rs|
            assert_single_read rs, typeof(value), value
          end
        end
      end

      it "insert/get value #{value_desc} from table", prepared: :both do |db|
        db.exec sql_create_table_table1(sql_type)
        db.exec sql_insert_table1(value_encoded)

        db.query_one(sql_select_table1, as: typeof(value)).should eq(value)
      end

      it "insert/get value #{value_desc} from table as nillable", prepared: :both do |db|
        db.exec sql_create_table_table1(sql_type)
        db.exec sql_insert_table1(value_encoded)

        db.query_one(sql_select_table1, as: ::Union(typeof(value) | Nil)).should eq(value)
      end

      it "insert/get value nil from table as nillable #{sql_type}", prepared: :both do |db|
        db.exec sql_create_table_table1(sql_type, null: true)
        db.exec sql_insert_table1(encode_null)

        db.query_one(sql_select_table1, as: ::Union(typeof(value) | Nil)).should eq(nil)
      end

      it "insert/get value #{value_desc} from table with binding" do |db|
        db.exec sql_create_table_table2(sql_type_for(String), sql_type)
        # the next statement will force a union in the *args
        db.exec sql_insert_table2(param(1), param(2)), value_for(String), value
        db.query_one(sql_select_table2_col2, as: typeof(value)).should eq(value)
      end

      it "insert/get value #{value_desc} from table as nillable with binding" do |db|
        db.exec sql_create_table_table2(sql_type_for(String), sql_type)
        # the next statement will force a union in the *args
        db.exec sql_insert_table2(param(1), param(2)), value_for(String), value
        db.query_one(sql_select_table2_col2, as: ::Union(typeof(value) | Nil)).should eq(value)
      end

      it "insert/get value nil from table as nillable #{sql_type} with binding" do |db|
        db.exec sql_create_table_table2(sql_type_for(String), sql_type, null: true)
        db.exec sql_insert_table2(param(1), param(2)), value_for(String), nil

        db.query_one(sql_select_table2_col2, as: ::Union(typeof(value) | Nil)).should eq(nil)
      end
    end

    # :nodoc:
    def include_shared_specs
      it "connects using connection_string" do |db|
        db.is_a?(DB::Database)
      end

      it "can create direct connection" do
        DB.connect(connection_string) do |cnn|
          cnn.is_a?(DB::Connection)
          cnn.scalar(select_scalar(encode_null)).should be_nil
        end
      end

      it "binds nil" do |db|
        db.scalar(select_scalar(param(1)), nil).should be_nil
      end

      it "selects nil as scalar", prepared: :both do |db|
        db.scalar(select_scalar(encode_null)).should be_nil
      end

      it "gets column count", prepared: :both do |db|
        db.exec sql_create_table_person
        db.query "select * from person" do |rs|
          rs.column_count.should eq(2)
        end
      end

      it "gets column name", prepared: :both do |db|
        db.exec sql_create_table_person

        db.query "select name, age from person" do |rs|
          rs.column_name(0).should eq("name")
          rs.column_name(1).should eq("age")
        end
      end

      it "gets many rows from table" do |db|
        db.exec sql_create_table_person
        db.exec sql_insert_person, "foo", 10
        db.exec sql_insert_person, "bar", 20
        db.exec sql_insert_person, "baz", 30

        names = [] of String
        ages = [] of Int32
        db.query sql_select_person do |rs|
          rs.each do
            names << rs.read(String)
            ages << rs.read(Int32)
          end
        end
        names.should eq(["foo", "bar", "baz"])
        ages.should eq([10, 20, 30])
      end

      # describe "transactions" do
      it "transactions: can read inside transaction and rollback after" do |db|
        db.exec sql_create_table_person
        db.transaction do |tx|
          tx.connection.scalar(sql_select_count_person).should eq(0)
          tx.connection.exec sql_insert_person, "John Doe", 10
          tx.connection.scalar(sql_select_count_person).should eq(1)
          tx.rollback
        end
        db.scalar(sql_select_count_person).should eq(0)
      end

      it "transactions: can read inside transaction or after commit" do |db|
        db.exec sql_create_table_person
        db.transaction do |tx|
          tx.connection.scalar(sql_select_count_person).should eq(0)
          tx.connection.exec sql_insert_person, "John Doe", 10
          tx.connection.scalar(sql_select_count_person).should eq(1)
          # using other connection
          db.scalar(sql_select_count_person).should eq(0)
        end
        db.scalar("select count(*) from person").should eq(1)
      end
      # end

      # describe "nested transactions" do
      it "nested transactions: can read inside transaction and rollback after" do |db|
        db.exec sql_create_table_person
        db.transaction do |tx_0|
          tx_0.connection.scalar(sql_select_count_person).should eq(0)
          tx_0.connection.exec sql_insert_person, "John Doe", 10
          tx_0.transaction do |tx_1|
            tx_1.connection.exec sql_insert_person, "Sarah", 11
            tx_1.connection.scalar(sql_select_count_person).should eq(2)
            tx_1.transaction do |tx_2|
              tx_2.connection.exec sql_insert_person, "Jimmy", 12
              tx_2.connection.scalar(sql_select_count_person).should eq(3)
              tx_2.rollback
            end
          end
          tx_0.connection.scalar(sql_select_count_person).should eq(2)
          tx_0.rollback
        end
        db.scalar(sql_select_count_person).should eq(0)
      end
      # end
    end

    def with_db(options = "")
      @before.call
      DB.open("#{connection_string}?#{options}") do |db|
        yield db
      end
      @after.call
    end

    # :nodoc:
    def select_scalar(expression)
      select_scalar_syntax.call(expression)
    end

    # :nodoc:
    def param(index)
      binding_syntax.call(index)
    end

    # :nodoc:
    def encode_null
      @encode_null
    end

    # :nodoc:
    def sql_type_for(a_class)
      value = @values.select { |v| v.value.class == a_class }.first?
      if value
        value.sql_type
      else
        raise "missing sample_value with #{a_class}"
      end
    end

    # :nodoc:
    macro value_for(a_class)
      _value_for({{a_class}}).as({{a_class}})
    end

    # :nodoc:
    def _value_for(a_class)
      value = @values.select { |v| v.value.class == a_class }.first?
      if value
        value.value
      else
        raise "missing sample_value with #{a_class}"
      end
    end

    # :nodoc:
    def sql_create_table_person
      create_table_2columns_syntax.call("person",
        ColumnDef.new("name", sql_type_for(String), false),
        ColumnDef.new("age", sql_type_for(Int32), false)
      )
    end

    # :nodoc:
    def sql_select_person
      select_2columns_syntax.call("person", "name", "age")
    end

    # :nodoc:
    def sql_insert_person
      insert_2columns_syntax.call("person", "name", param(1), "age", param(2))
    end

    # :nodoc:
    def sql_select_count_person
      select_count_syntax.call("person")
    end

    # :nodoc:
    def sql_create_table_table1(sql_type, *, null = false)
      create_table_1column_syntax.call("table1",
        ColumnDef.new("col1", sql_type, null)
      )
    end

    # :nodoc:
    def sql_create_table_table2(sql_type1, sql_type2, *, null = false)
      create_table_2columns_syntax.call("table2",
        ColumnDef.new("col1", sql_type1, null),
        ColumnDef.new("col2", sql_type2, null)
      )
    end

    # :nodoc:
    def sql_insert_table1(expression)
      insert_1column_syntax.call("table1", "col1", expression)
    end

    # :nodoc:
    def sql_insert_table2(expr1, expr2)
      insert_2columns_syntax.call("table2", "col1", expr1, "col2", expr2)
    end

    # :nodoc:
    def sql_select_table1
      select_1column_syntax.call("table1", "col1")
    end

    # :nodoc:
    def sql_select_table2_col2
      select_1column_syntax.call("table2", "col2")
    end

    def self.run(description = "as a db")
      ctx = self.new
      with ctx yield

      describe description do
        ctx.include_shared_specs

        ctx.its.each do |db_it|
          case db_it.prepared
          when :default
            it(db_it.description, db_it.file, db_it.line, db_it.end_line) do
              ctx.with_db do |db|
                db_it.block.call db
                nil
              end
            end
          when :both
            [true, false].each do |prepared_statements|
              it("#{db_it.description} (prepared_statements=#{prepared_statements})", db_it.file, db_it.line, db_it.end_line) do
                ctx.with_db "prepared_statements=#{prepared_statements}" do |db|
                  db_it.block.call db
                  nil
                end
              end
            end
          end
        end

      end
    end
  end
end
