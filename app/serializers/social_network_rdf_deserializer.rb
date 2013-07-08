require "fruchterman_reingold"

class SocialNetworkRDFDeserializer
  def initialize(user, data)
    @data = data
    @user = user
    @fix_position = false
    initialize_graph
  end

  def initialize_graph
    @graph = RDF::Graph.new
    RDF::N3::Reader.new(@data).each do |statement|
      @graph << statement
    end
  end

  def deserialize!
    extract_vocabulary
    deserialize_social_network
    deserialize_families
    deserialize_nodes
    deserialize_node_families
    deserialize_roles
    deserialize_attributes
    apply_layout if @fix_position
    @social_network
  end

  def extract_vocabulary
    md = @data.match(/@prefix\s+sn:\s+\<(?<vocabulary>.*)\>/)
    @sn = RDF::Vocabulary.new(md[:vocabulary])
  end

  def deserialize_social_network
    query = RDF::Query.new({
      social_network: { RDF.type  => @sn.socialNetwork, @sn.name => :name, }
    })
    result = query.execute(@graph).first
    puts result
    name = result.name.value rescue "New Social Network"
    @social_network = @user.social_networks.create!({ name: name })
  end

  def deserialize_families
    query = RDF::Query.new do |q|
      q.pattern [:family, RDF.type, @sn.family]
      q.pattern [:family, @sn.name, :name]
      q.pattern [:family, @sn.kind, :kind]
      q.pattern [:family, @sn.color, :color], optional: true
    end
    @families ||= {}
    query.execute(@graph).each do |result|
      params = {}
      params[:name] = result.name.value
      params[:kind] = result.kind.value
      params[:color] = begin
                         result.color.value
                       rescue NoMethodError
                         assign_color
                       end
      @families[result.family.to_s] = @social_network.families.create!(params)
    end
  end

  def deserialize_nodes
    query = RDF::Query.new do |q|
      q.pattern [:node, RDF.type, :type]
      q.pattern [:node, @sn.name, :name]
      q.pattern [:node, @sn.positionX, :x], optional: true
      q.pattern [:node, @sn.positionY, :y], optional: true
    end
    @nodes ||= {}
    result = query.execute(@graph).filter do |result|
      result.type == @sn.actor || result.type == @sn.relation
    end
    range_x = (20..50*result.length)
    range_y = (20..50*result.length)
    result.each do |result|
      params = {}
      params[:name] = result.name.value
      params[:kind] = result.type.to_s.match(/#(.*)/)[1].titleize
      params[:x] = begin
                     result.x.value 
                   rescue NoMethodError
                     @fix_position = true
                     rand(range_x)
                   end
      params[:y] = begin
                     result.y.value 
                   rescue NoMethodError
                     @fix_position = true
                     rand(range_y)
                   end
      @nodes[result.node.to_s] = @social_network.nodes.create!(params)
    end
  end

  def deserialize_node_families
    query = RDF::Query.new({ node: {
      @sn.belongsToFamily => :family
    }})
    query.execute(@graph).each do |result|
      node = @nodes[result.node.to_s]
      family = @families[result.family.to_s]
      node.family_ids = node.family_ids + [family.id]
    end
  end

  def deserialize_roles
    q1 = RDF::Query.new({ actor: { RDF.type => @sn.actor, @sn.participatesAs => :role, } })
    q2 = RDF::Query.new({ role: { RDF.type => @sn.role, @sn.inRelation => :relation, @sn.name => :name }})
    r1 = q1.execute(@graph)
    r2 = q2.execute(@graph, solutions: r1)
    r2.each_solution do |solution|
      @social_network.roles.create!({
        name: solution.name.value,
        actor_id: @nodes[solution.actor.to_s].id,
        relation_id: @nodes[solution.relation.to_s].id,
      })
    end
  end

  def deserialize_attributes
    query = RDF::Query.new({ node: { RDF.type => :type, :predicate => :literal } })
    solutions = query.execute(@graph)
    solutions.filter! do |solution|
      kind = vocabulary_element_from_uri(solution.type).titleize
      predicateElement = vocabulary_element_from_uri(solution.predicate)
      (kind == "Actor" || kind == "Relation") && predicateElement.match(/attribute/)
    end
    solutions.each do |solution|
      predicate = vocabulary_element_from_uri(solution.predicate)
      key = predicate.match(/attribute(.*)/)[1]
      @nodes[solution.node.to_s].node_attributes.create!({
        key: key,
        value: solution.literal.value,
      })
    end
  end

  def statements
    if @statements.nil?
      @statements = []
      @graph.each_statement do |statement|
        @statements << statement
      end
    end
    @statements
  end

  def apply_layout
    nodes = {}
    @social_network.nodes.each do |node|
      position = FruchtermanReingold::Coordinates.new(node.x, node.y)
      disposition = FruchtermanReingold::Coordinates.new(0, 0)
      nodes[node.id] = FruchtermanReingold::Node.new(position, disposition)
    end

    edges = {}
    @social_network.roles.each do |role|
      begining = nodes[role.actor.id]
      end_node = nodes[role.relation.id]
      edges[role.id] = FruchtermanReingold::Edge.new(begining, end_node)
    end

    g = FruchtermanReingold::Graph.new
    g.nodes = nodes.values
    g.edges = edges.values

    g.draw

    min_x = g.nodes.min_by { |node| node.position.x }.position.x
    min_y = g.nodes.min_by { |node| node.position.y }.position.y

    @social_network.nodes.each_with_index do |node, index|
      node.x = g.nodes[index].position.x - min_x + 40
      node.y = g.nodes[index].position.y - min_y + 40
      node.save
    end
  end

  private

  def vocabulary_element_from_uri(uri)
    uri.to_s.match(/.*#(?<element>.*)$/)[:element]
  end

  def assign_color
    @colors ||= [ "#5254a3", "#6b6ecf", "#9c9ede", "#637939", "#8ca252",
                  "#b5cf6b", "#cedb9c", "#8c6d31", "#bd9e39", "#e7ba52",
                  "#e7cb94", "#843c39", "#ad494a", "#d6616b", "#e7969c",
                  "#7b4173", "#a55194", "#ce6dbd", "#de9ed6", "#ff7f0e",
                  "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2",
                  "#7f7f7f", "#bcbd22", "#17becf" ]
    @colors.sample
  end
end
