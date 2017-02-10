require_relative './utilities'
include Utils

def max_of_example
  execute_statement session, 'drop table', %[DROP TABLE IF EXISTS test]
  execute_statement session, 'create table', %[
    CREATE TABLE test (
        id int,
        val1 int,
        val2 int,
        PRIMARY KEY(id)
    );
  ]

  execute_statement session, 'create maxOf function', %[
    CREATE OR REPLACE FUNCTION maxOf(current int, testvalue int)
    CALLED ON NULL INPUT
    RETURNS int
    LANGUAGE java
    AS $$
      if (current == null && testvalue == null) {
        return null;
      } else if (current == null) {
        return testvalue;
      } else if (testvalue == null) {
        return current;
      } else {
        return Math.max(current,testvalue);
      }
    $$;
  ]

  execute_statement session, 'insert', %[INSERT INTO test(id, val1, val2) VALUES(1, 100, 200);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val1) VALUES(2, 100);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val2) VALUES(3, 200);]

  query = session.prepare 'SELECT id, val1, val2, maxOf(val1, val2) as max FROM test'
  result = session.execute query

  puts "maxOf results:"
  result.rows.each do |row|
    puts "  " + JSON.generate(row)
  end
end

# Using aggregates
def sum_of_example
  session = connect!

  # CREATE FUNCTION function_name(stateArg type0, arg1 type1)
  #     RETURNS NULL ON NULL INPUT
  #     RETURNS type0
  #     LANGUAGE java
  #     AS 'return (type0) stateArg + arg1';
  #
  # CREATE AGGREGATE aggregate_name(type0)
  #     SFUNC function_name
  #     STYPE type0
  #     FINALFUNC function_name2
  #     INITCOND null;

  execute_statement session, 'drop table', %[DROP TABLE IF EXISTS test]
  execute_statement session, 'create table', %[
    CREATE TABLE test (
        id int,
        val int,
        PRIMARY KEY(id)
    );
  ]

  execute_statement session, 'create sumOfOddFunc function', %[
    CREATE OR REPLACE FUNCTION sumOfOddFunc(sum int, current int)
    CALLED ON NULL INPUT
    RETURNS int
    LANGUAGE java
    AS $$
      if (current == null) {
        return sum;
      } else if (current % 2 != 0) {
        return sum + current;
      } else {
        return sum;
      }
    $$;
  ]

  execute_statement session, 'create sumOfOdd aggregate', %[
    CREATE OR REPLACE AGGREGATE sumOfOdd(int)
    SFUNC sumOfOddFunc
    STYPE int
    INITCOND 0;
  ]

  execute_statement session, 'insert', %[INSERT INTO test(id, val) VALUES(1, 101);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val) VALUES(2, 100);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val) VALUES(3, 201);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val) VALUES(4, 1);]
  execute_statement session, 'insert', %[INSERT INTO test(id) VALUES(5);]
  execute_statement session, 'insert', %[INSERT INTO test(id, val) VALUES(6, 8);]

  query = session.prepare 'SELECT sumOfOdd(val) FROM test'
  result = session.execute query

  puts "sumOfOdd result:"
  result.rows.each do |row|
    puts "  " + JSON.generate(row)
  end
end

# sum_of_example
def data_stream_example
  session = connect!

  # CREATE FUNCTION function_name(stateArg type0, arg1 type1)
  #     RETURNS NULL ON NULL INPUT
  #     RETURNS type0
  #     LANGUAGE java
  #     AS 'return (type0) stateArg + arg1';
  #
  # CREATE AGGREGATE aggregate_name(type0)
  #     SFUNC function_name
  #     STYPE type0
  #     FINALFUNC function_name2
  #     INITCOND null;

  execute_statement session, 'drop table', %[DROP TABLE IF EXISTS test]
  execute_statement session, 'create table', %[
    CREATE TABLE test (
      id int,
      val int,
      PRIMARY KEY (id)
    );
  ]

  execute_statement session, 'drop aggregate', 'DROP AGGREGATE IF EXISTS nthRecord(int, int);'
  execute_statement session, 'drop aggregate', 'DROP AGGREGATE IF EXISTS nthRecord(int);'

  execute_statement session, 'drop func', 'DROP FUNCTION IF EXISTS nthCollector(tuple<int, map<int, int>>, int);'
  execute_statement session, 'drop func', 'DROP FUNCTION IF EXISTS nthCollector(tuple<int, list<int>>, int);'
  execute_statement session, 'drop func', 'DROP FUNCTION IF EXISTS nthCollector(tuple<int, list<int>>, int, int);'

  execute_statement session, 'create nthCollector function', %[
    CREATE OR REPLACE FUNCTION nthCollector(state tuple<int, map<int, int>>, current int, nthval int)
    CALLED ON NULL INPUT
    RETURNS tuple<int, map<int, int>>
    LANGUAGE java
    AS $$
      state.setInt(0, state.getInt(0) + 1);

      if (state.getInt(0) % nthval == 0) {
        Map<Integer, Integer> existing;
        if (state.getMap(1, Integer.class, Integer.class) == null) {
          existing = new HashMap<Integer, Integer>();
        } else {
          existing = state.getMap(1, Integer.class, Integer.class);
        }
        existing.put(state.getInt(0), current);
        state.setMap(1, existing);
      }


      return state;
    $$;
  ]


  execute_statement session, 'create nthFinal function', %[
    CREATE OR REPLACE FUNCTION nthFinal(state tuple<int, map<int, int>>)
    CALLED ON NULL INPUT
    RETURNS map<int, int>
    LANGUAGE java
    AS $$
      return state.getMap(1, Integer.class, Integer.class);
    $$;
  ]


  execute_statement session, 'create nthRecord aggregate', %[
    CREATE OR REPLACE AGGREGATE nthRecord(int, int)
    SFUNC nthCollector
    STYPE tuple<int, map<int, int>>
    FINALFUNC nthFinal
    INITCOND (0, {});
  ]

  insert = session.prepare %[INSERT INTO test(id, val) VALUES(?, ?);]
  100.times {|n| session.execute insert, arguments: [n, n] }

  query = session.prepare 'SELECT nthRecord(val, 2) as val_collection FROM test'
  result = session.execute query

  puts "maxOf results:"
  result.rows.each do |row|
    puts "  " + JSON.generate(row)
  end
end

data_stream_example
