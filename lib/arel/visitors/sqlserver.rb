module Arel
  module Visitors
    class SQLServer < Arel::Visitors::ToSql
      
      
      private
      
      # SQLServer ToSql/Visitor (Overides)
      
      def visit_Arel_Nodes_SelectStatement(o)
        if complex_count_sql?(o)
          visit_Arel_Nodes_SelectStatementForComplexCount(o)
        elsif o.offset
          visit_Arel_Nodes_SelectStatementWithOffset(o)
        else
          visit_Arel_Nodes_SelectStatementWithOutOffset(o)
        end
      end
      
      def visit_Arel_Nodes_Offset(o)
        "WHERE [__rnt].[__rn] > #{visit o.expr}"
      end
      
      def visit_Arel_Nodes_Limit(o)
        "TOP (#{visit o.expr})"
      end
      
      
      # SQLServer ToSql/Visitor (Additions)
      
      def visit_Arel_Nodes_SelectStatementWithOutOffset(o, windowed=false)
        core = o.cores.first
        projections = core.projections
        if windowed && !function_select_statement?(o)
          projections =  projections.map { |x| projection_without_expression(x) }
        elsif eager_limiting_select?(o)
          
        end
        [ ("SELECT" if !windowed),
          (visit(o.limit) if o.limit && !windowed),
          (projections.map{ |x| visit(x) }.join(', ')),
          ("FROM #{visit core.froms}" if core.froms),
          (visit(o.lock) if o.lock),
          # (joins unless joins.blank?),
          ("WHERE #{core.wheres.map{ |x| visit(x) }.join ' AND ' }" unless core.wheres.empty?),
          ("GROUP BY #{core.groups.map { |x| visit x }.join ', ' }" unless core.groups.empty?),
          (visit(core.having) if core.having),
          ("ORDER BY #{o.orders.map{ |x| visit(x) }.join(', ')}" if !o.orders.empty? && !windowed)
        ].compact.join ' '
      end
      
      def visit_Arel_Nodes_SelectStatementWithOffset(o)
        orders = rowtable_orders(o)
        [ "SELECT",
          (visit(o.limit) if o.limit && !single_distinct_select?(o)),
          (rowtable_projections(o).map{ |x| visit(x) }.join(', ')),
          "FROM (",
            "SELECT ROW_NUMBER() OVER (ORDER BY #{orders.map{ |x| visit(x) }.uniq.join(', ')}) AS [__rn],",
            visit_Arel_Nodes_SelectStatementWithOutOffset(o,true),
          ") AS [__rnt]",
          (visit(o.offset) if o.offset),
        ].compact.join ' '
      end
      
      def visit_Arel_Nodes_SelectStatementForComplexCount(o)
        
      end
      
      
      # SQLServer Helpers
      
      def table_name_from_select_statement(o)
        o.cores.first.source.left.name
      end
      
      def single_distinct_select?(o)
        projections = o.cores.first.projections
        projections.size == 1 && projections.first.include?('DISTINCT')
      end
      
      def function_select_statement?(o)
        core = o.cores.first
        core.projections.any? { |x| Arel::Nodes::Function === x }
      end
      
      def eager_limiting_select?(o)
        false
        # single_distinct_select?(o) && taken_only? && relation.group_clauses.blank?
      end
      
      def complex_count_sql?(o)
        false
        # projections = relation.projections
        # projections.first.is_a?(Arel::Count) && projections.size == 1 &&
        #   (relation.taken.present? || relation.wheres.present?) && relation.joins(self).blank?
      end
      
      def rowtable_projections(o)
        core = o.cores.first
        if single_distinct_select?(o)
          raise 'TODO: single_distinct_select'
          # ::Array.wrap(relation.select_clauses.first.dup.tap do |sc|
          #   sc.sub! 'DISTINCT', "DISTINCT #{taken_clause if relation.taken.present?}".strip
          #   sc.sub! table_name_from_select_clause(sc), '__rnt'
          #   sc.strip!
          # end)
        elsif false # relation.join? && all_select_clauses_aliased?
          raise 'TODO: relation.join? && all_select_clauses_aliased?'
          # relation.select_clauses.map do |sc|
          #   sc.split(',').map { |c| c.split(' AS ').last.strip  }.join(', ')
          # end
        elsif function_select_statement?(o)
          [Arel.star]
        else
          tn = table_name_from_select_statement(o)
          core.projections.map { |x| x.gsub /\[#{tn}\]\./, '[__rnt].' }
        end
      end
      
      def rowtable_orders(o)
        if !o.orders.empty?
          o.orders
        elsif false # TODO relation.join?
          # table_names_from_select_clauses.map { |tn| quote("#{tn}.#{pk_for_table(tn)}") }
        else
          tn = table_name_from_select_statement(o)
          [Arel::Table.new(tn, @engine).primary_key.asc]
        end
      end
      
      def projection_without_expression(projection)
        projection.to_s.split(',').map do |x|
          x.strip!
          x.sub!(/^(COUNT|SUM|MAX|MIN|AVG)\s*(\((.*)\))?/,'\3')
          x.sub!(/^DISTINCT\s*/,'')
          x.sub!(/TOP\s*\(\d+\)\s*/i,'')
          x.strip
        end.join(', ')
      end
      
    end
  end
end

Arel::Visitors::VISITORS['sqlserver'] = Arel::Visitors::SQLServer
