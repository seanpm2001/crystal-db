module DB
  # Represents a prepared query in a `Connection`.
  # It should be created by `QueryMethods`.
  #
  # ### Note to implementors
  #
  # 1. Subclass `Statements`
  # 2. `Statements` are created from a custom driver `Connection#prepare` method.
  # 3. `#perform_query` executes a query that is expected to return a `ResultSet`
  # 4. `#perform_exec` executes a query that is expected to return an `ExecResult`
  # 6. `#do_close` is called to release the statement resources.
  abstract class Statement
    include Disposable

    # :nodoc:
    getter connection

    def initialize(@connection : Connection)
    end

    protected def do_close
    end

    def release_connection
      @connection.database.return_to_pool(@connection)
    end

    # See `QueryMethods#exec`
    def exec
      perform_exec_and_release(Slice(Any).new(0))
    end

    # See `QueryMethods#exec`
    def exec(args : Array)
      perform_exec_and_release(args)
    end

    # See `QueryMethods#exec`
    def exec(*args)
      # TODO better way to do it
      perform_exec_and_release(args)
    end

    # See `QueryMethods#scalar`
    def scalar(*args)
      query(*args) do |rs|
        rs.each do
          # return case rs.read?(rs.column_type(0)) # :-( Some day...
          case rs.column_type(0)
          when String.class
            return rs.read?(String)
          when Int32.class
            return rs.read?(Int32)
          when Int64.class
            return rs.read?(Int64)
          when Float32.class
            return rs.read?(Float32)
          when Float64.class
            return rs.read?(Float64)
          when Bytes.class
            return rs.read?(Bytes)
          when Nil.class
            return rs.read?(Int32)
          else
            raise "not implemented for #{rs.column_type(0)} type"
          end
        end
      end

      raise "no results"
    end

    # See `QueryMethods#query`
    def query
      perform_query Slice(Any).new(0)
    end

    # See `QueryMethods#query`
    def query(args : Array)
      perform_query args
    end

    # See `QueryMethods#query`
    def query(*args)
      perform_query args
    end

    # See `QueryMethods#query`
    def query(*args)
      query(*args).tap do |rs|
        begin
          yield rs
        ensure
          rs.close
        end
      end
    end

    private def perform_exec_and_release(args : Enumerable) : ExecResult
      perform_exec(args).tap do
        release_connection
      end
    end

    protected abstract def perform_query(args : Enumerable) : ResultSet
    protected abstract def perform_exec(args : Enumerable) : ExecResult
  end
end
