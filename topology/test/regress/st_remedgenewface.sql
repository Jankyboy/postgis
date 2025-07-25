\set VERBOSITY terse
set client_min_messages to ERROR;

-- Import city_data
\i :top_builddir/topology/test/load_topology-4326.sql

-- Utility functions for the test {

CREATE TEMP TABLE orig_node_summary(node_id int8, containing_face int8);
CREATE OR REPLACE FUNCTION save_nodes()
RETURNS VOID
AS $$
  TRUNCATE TABLE orig_node_summary;
  INSERT INTO orig_node_summary
  SELECT node_id,
    containing_face
    FROM city_data.node;
$$ LANGUAGE 'sql';

CREATE OR REPLACE FUNCTION check_nodes(lbl text)
RETURNS TABLE (l text, o text, node_id int8,
    containing_face int8)
AS $$
DECLARE
  sql1 text;
  sql2 text;
  q text;
BEGIN
  sql1 := 'node_id,
      containing_face
  		FROM city_data.node';
  sql2 := 'node_id, containing_face
  		FROM orig_node_summary';

  q := format(
    $SQL$
      (
          SELECT %1$L, '+' as op, %2$s
            EXCEPT
          SELECT %1$L, '+', %3$s
      ) UNION ALL (
          SELECT %1$L, '-', %3$s
            EXCEPT
          SELECT %1$L, '-', %2$s
      )
      ORDER BY node_id, op
    $SQL$,
    lbl,
    sql1,
    sql2
  );

  RAISE DEBUG '%', q;

  RETURN QUERY EXECUTE q;

END
$$ LANGUAGE 'plpgsql';

CREATE TEMP TABLE orig_edge_summary (edge_id int8, next_left_edge int8, next_right_edge int8, left_face int8, right_face int8);
CREATE OR REPLACE FUNCTION save_edges()
RETURNS VOID
AS $$
  TRUNCATE orig_edge_summary;
  INSERT INTO orig_edge_summary
  SELECT edge_id,
    next_left_edge, next_right_edge, left_face, right_face
    FROM city_data.edge_data;
$$ LANGUAGE 'sql';

CREATE OR REPLACE FUNCTION check_edges(lbl text)
RETURNS TABLE (l text, o text, edge_id int8,
    next_left_edge int8, next_right_edge int8,
    left_face int8, right_face int8)
AS $$
DECLARE
  rec RECORD;
  sql1 text;
  sql2 text;
  q text;
BEGIN
  sql1 := 'edge_id,
      next_left_edge, next_right_edge, left_face, right_face
  		FROM city_data.edge_data';
  sql2 := 'edge_id,
  		next_left_edge, next_right_edge, left_face, right_face
  		FROM orig_edge_summary';

  q := format(
    $SQL$
      (
          SELECT %1$L, '+' as op, %2$s
            EXCEPT
          SELECT %1$L, '+', %3$s
      ) UNION ALL (
          SELECT %1$L, '-', %3$s
            EXCEPT
          SELECT %1$L, '-', %2$s
      )
      ORDER BY edge_id, op
    $SQL$,
    lbl,
    sql1,
    sql2
  );

  RAISE DEBUG '%', q;

  RETURN QUERY EXECUTE q;

END
$$ LANGUAGE 'plpgsql';

CREATE TEMP TABLE orig_face_summary(face_id int8, mbr geometry);
CREATE OR REPLACE FUNCTION save_faces()
RETURNS VOID
AS $$
  TRUNCATE orig_face_summary;
  INSERT INTO orig_face_summary
  SELECT face_id, mbr
    FROM city_data.face;
$$ LANGUAGE 'sql';

CREATE OR REPLACE FUNCTION check_faces(lbl text)
RETURNS TABLE (l text, o text, face_id int8, mbr text)
AS $$
DECLARE
  sql1 text;
  sql2 text;
  q text;
BEGIN
  sql1 := 'face_id, ST_AsEWKT(mbr) FROM city_data.face';
  sql2 := 'face_id, ST_AsEWKT(mbr) FROM orig_face_summary';

  q := format(
    $SQL$
      (
          SELECT %1$L, '+' as op, %2$s
            EXCEPT
          SELECT %1$L, '+', %3$s
      ) UNION ALL (
          SELECT %1$L, '-' as op, %3$s
            EXCEPT
          SELECT %1$L, '-' as op, %2$s
      )
      ORDER BY face_id, op
    $SQL$,
    lbl,
    sql1,
    sql2
  );


  RAISE DEBUG '%', q;

  RETURN QUERY EXECUTE q;

END
$$ language 'plpgsql';

-- Runs a query and returns whether an error was thrown
-- Useful when the error message depends on the execution plan taken (parallelism)
CREATE OR REPLACE FUNCTION catch_error(query text)
RETURNS bool
AS $$
BEGIN
    EXECUTE query;
    RETURN FALSE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN TRUE;
END
$$ LANGUAGE 'plpgsql';

-- }

-- Save current state
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Bogus calls -- {
SELECT topology.ST_RemEdgeNewFace('city_data', null);
SELECT topology.ST_RemEdgeNewFace(null, 1);
SELECT topology.ST_RemEdgeNewFace('', 1);
SELECT topology.ST_RemEdgeNewFace('city_data', 0); -- non-existent
SELECT topology.ST_RemEdgeNewFace('city_data', 143); -- non-existent
SELECT * FROM check_nodes('bogus');
SELECT * FROM check_edges('bogus');
SELECT * FROM check_faces('bogus');
-- }

-- Remove isolated edge
SELECT 'RN(25)', topology.ST_RemEdgeNewFace('city_data', 25);
SELECT * FROM check_nodes('RN(25)/nodes');
SELECT * FROM check_edges('RN(25)/edges');
SELECT * FROM check_faces('RN(25)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Remove edge not forming a ring
SELECT 'RN(4)', topology.ST_RemEdgeNewFace('city_data', 4);
SELECT * FROM check_nodes('RN(4)/nodes');
SELECT * FROM check_edges('RN(4)/edges');
SELECT * FROM check_faces('RN(4)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Heal faces 1 and 9 -- should drop them and create a new face
-- New face has the same mbr as old one
SELECT 'RN(26)', topology.ST_RemEdgeNewFace('city_data', 26);
SELECT * FROM check_nodes('RN(26)/nodes');
SELECT * FROM check_edges('RN(26)/edges');
SELECT * FROM check_faces('RN(26)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Heal faces 3 and 6 -- should drop them and create a new face
-- New face has a mbr being the union of the dropped faces
SELECT 'RN(9)', topology.ST_RemEdgeNewFace('city_data', 9);
SELECT * FROM check_nodes('RN(9)/nodes');
SELECT * FROM check_edges('RN(9)/edges');
SELECT * FROM check_faces('RN(9)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Heal faces 4 and 11 -- should drop them and create a new face
-- New face has a mbr being the union of the dropped faces
SELECT 'RN(19)', topology.ST_RemEdgeNewFace('city_data', 19);
SELECT * FROM check_nodes('RN(19)/nodes');
SELECT * FROM check_edges('RN(19)/edges');
SELECT * FROM check_faces('RN(19)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Heal faces 7 and 12 -- should drop them and create a new face
-- New face has a mbr equal to previous face 12.
-- This healing leaves edge 20 dangling
SELECT 'RN(10)', topology.ST_RemEdgeNewFace('city_data', 10);
SELECT * FROM check_nodes('RN(10)/nodes');
SELECT * FROM check_edges('RN(10)/edges');
SELECT * FROM check_faces('RN(10)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Drop dangling edge, no faces change
SELECT 'RN(20)', topology.ST_RemEdgeNewFace('city_data', 20);
SELECT * FROM check_nodes('RN(20)/nodes');
SELECT * FROM check_edges('RN(20)/edges');
SELECT * FROM check_faces('RN(20)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing face
SELECT 'RN(15)', topology.ST_RemEdgeNewFace('city_data', 15);
SELECT * FROM check_nodes('RN(15)/nodes');
SELECT * FROM check_edges('RN(15)/edges');
SELECT * FROM check_faces('RN(15)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge starting from the closing node and
-- going inside.
-- Closed edge is in CW order.
SELECT 'RN(2)', topology.ST_RemEdgeNewFace('city_data', 2);
SELECT * FROM check_nodes('RN(2)/nodes');
SELECT * FROM check_edges('RN(2)/edges');
SELECT * FROM check_faces('RN(2)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge coming from inside and ending to the closing node
-- Closed edge is in CW order.
-- Requires reconstructing the outer ring
SELECT 'NE(27)', topology.ST_AddEdgeNewFaces('city_data', 3, 3, 'SRID=4326;LINESTRING(25 35, 30 27, 20 27, 25 35)');
SELECT * FROM check_nodes('NE(27)/nodes');
SELECT * FROM check_edges('NE(27)/edges');
SELECT * FROM check_faces('NE(27)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(27)', topology.ST_RemEdgeNewFace('city_data', 27);
SELECT * FROM check_nodes('RN(27)/nodes');
SELECT * FROM check_edges('RN(27)/edges');
SELECT * FROM check_faces('RN(27)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge coming from inside and ending to the closing node
-- Closed edge is in CCW order.
-- Requires reconstructing the outer ring
SELECT 'NE(28)', topology.ST_AddEdgeNewFaces('city_data', 3, 3, 'SRID=4326;LINESTRING(25 35, 20 27, 30 27, 25 35)');
SELECT * FROM check_nodes('NE(28)/nodes');
SELECT * FROM check_edges('NE(28)/edges');
SELECT * FROM check_faces('NE(28)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(28)', topology.ST_RemEdgeNewFace('city_data', 28);
SELECT * FROM check_nodes('RN(28)/nodes');
SELECT * FROM check_edges('RN(28)/edges');
SELECT * FROM check_faces('RN(28)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge starting from closing node and going inside.
-- Closed edge is in CCW order.
-- Requires reconstructing the outer ring
SELECT 'NE(29)', topology.ST_AddEdgeNewFaces('city_data', 2, 2, 'SRID=4326;LINESTRING(25 30, 28 37, 22 37, 25 30)');
SELECT * FROM check_nodes('NE(29)/nodes');
SELECT * FROM check_edges('NE(29)/edges');
SELECT * FROM check_faces('NE(29)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(29)', topology.ST_RemEdgeNewFace('city_data', 29);
SELECT * FROM check_nodes('RN(29)/nodes');
SELECT * FROM check_edges('RN(29)/edges');
SELECT * FROM check_faces('RN(29)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edges both inside and outside
-- Closed edge in CW order.
-- Requires adding an edge and reconstructing the outer ring
SELECT 'NE(30)', topology.ST_AddEdgeNewFaces('city_data', 4, 3, 'SRID=4326;LINESTRING(20 37, 25 35)');
SELECT 'NE(31)', topology.ST_AddEdgeNewFaces('city_data', 3, 3, 'SRID=4326;LINESTRING(25 35, 18 35, 18 40, 25 35)');
SELECT * FROM check_nodes('NE(30,31)/nodes');
SELECT * FROM check_edges('NE(30,31)/edges');
SELECT * FROM check_faces('NE(30,31)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(31)', topology.ST_RemEdgeNewFace('city_data', 31);
SELECT * FROM check_nodes('RN(31)/nodes');
SELECT * FROM check_edges('RN(31)/edges');
SELECT * FROM check_faces('RN(31)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edges both inside
-- Closed edge in CW order.
-- Requires reconstructing the outer ring
SELECT 'NE(32)', topology.ST_AddEdgeNewFaces('city_data', 3, 3, 'SRID=4326;LINESTRING(25 35, 18 35, 18 40, 28 40, 28 27, 18 27, 25 35)');
SELECT * FROM check_nodes('NE(32)/nodes');
SELECT * FROM check_edges('NE(32)/edges');
SELECT * FROM check_faces('NE(32)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(32)', topology.ST_RemEdgeNewFace('city_data', 32);
SELECT * FROM check_nodes('RN(32)/nodes');
SELECT * FROM check_edges('RN(32)/edges');
SELECT * FROM check_faces('RN(32)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edges both inside
-- Closed edge in CCW order.
-- Requires reconstructing the outer ring
SELECT 'NE(33)', topology.ST_AddEdgeNewFaces('city_data', 3, 3,
  'SRID=4326;LINESTRING(25 35,18 27,28 27,28 40,18 40,18 35,25 35)');
SELECT * FROM check_nodes('NE(33)/nodes');
SELECT * FROM check_edges('NE(33)/edges');
SELECT * FROM check_faces('NE(33)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(33)', topology.ST_RemEdgeNewFace('city_data', 33);
SELECT * FROM check_nodes('RN(33)/nodes');
SELECT * FROM check_edges('RN(33)/edges');
SELECT * FROM check_faces('RN(33)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge starting from closing node and going outside.
-- Closed edge is in CW order.
-- Requires reconstructing the outer ring
SELECT 'NE(34)', topology.ST_AddEdgeNewFaces('city_data', 2, 2,
 'SRID=4326;LINESTRING(25 30, 28 27, 22 27, 25 30)');
SELECT * FROM check_nodes('NE(34)/nodes');
SELECT * FROM check_edges('NE(34)/edges');
SELECT * FROM check_faces('NE(34)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(34)', topology.ST_RemEdgeNewFace('city_data', 34);
SELECT * FROM check_nodes('RN(34)/nodes');
SELECT * FROM check_edges('RN(34)/edges');
SELECT * FROM check_faces('RN(34)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

-- Universe flooding existing single-edge (closed) face
-- with dangling edge starting from closing node and going outside.
-- Closed edge is in CCW order.
-- Requires reconstructing the outer ring
SELECT 'NE(35)', topology.ST_AddEdgeNewFaces('city_data', 2, 2,
 'SRID=4326;LINESTRING(25 30,22 27,28 27,25 30)'
);
SELECT * FROM check_nodes('NE(35)/nodes');
SELECT * FROM check_edges('NE(35)/edges');
SELECT * FROM check_faces('NE(35)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();
-- Here's the removal
SELECT 'RN(35)', topology.ST_RemEdgeNewFace('city_data', 35);
SELECT * FROM check_nodes('RN(35)/nodes');
SELECT * FROM check_edges('RN(35)/edges');
SELECT * FROM check_faces('RN(35)/faces');
SELECT save_edges(); SELECT save_faces(); SELECT save_nodes();

SELECT topology.DropTopology('city_data');

-------------------------------------------------------------------------
-- Now test in presence of features
-------------------------------------------------------------------------
-- {

-- Import city_data
\i :top_builddir/topology/test/load_topology.sql
\i ../load_features.sql
\i ../cache_geometries.sql

-- A city_street is defined by edge 3, can't drop
SELECT '*RN(3)', topology.ST_RemEdgeNewFace('city_data', 3);
-- A city_street is defined by edge 4 and 5, can't drop any of the two
SELECT '*RN(4)', topology.ST_RemEdgeNewFace('city_data', 4);
SELECT '*RN(5)', topology.ST_RemEdgeNewFace('city_data', 5);

-- Two land_parcels (P2 and P3) are defined by either face
-- 5 but not face 4 or by face 4 but not face 5, so we can't heal
-- the faces by dropping edge 17
SELECT '*RN(17)', catch_error($$SELECT topology.ST_RemEdgeNewFace('city_data', 17)$$);

-- Dropping edge 11 is fine as it heals faces 5 and 8, which
-- only serve definition of land_parcel P3 which contains both
SELECT 'RN(11)', 'relations_before:', count(*) FROM city_data.relation;
SELECT 'RN(11)', topology.ST_RemEdgeNewFace('city_data', 11);
SELECT 'RN(11)', 'relations_after:', count(*) FROM city_data.relation;

-- Land parcel P3 is now defined by face 10, so we can't drop
-- any edge which would destroy that face.
SELECT '*RM(8)', topology.ST_RemEdgeNewFace('city_data', 8); -- face_right=10
SELECT '*RM(15)', topology.ST_RemEdgeNewFace('city_data', 15); -- face_left=10

-- Check that no land_parcel objects had topology changed
SELECT 'RN(11)', feature_name,
 ST_Equals( ST_Multi(feature::geometry), ST_Multi(the_geom) ) as unchanged
 FROM features.land_parcels;

SELECT topology.DropTopology('city_data');
DROP SCHEMA features CASCADE;

-- }
-------------------------------------------------------------------------
-------------------------------------------------------------------------
-------------------------------------------------------------------------

-------------------------------------------------------------------------
-- Test for https://trac.osgeo.org/postgis/ticket/5106
-------------------------------------------------------------------------

BEGIN;
SELECT NULL FROM topology.CreateTopology('t5106');
INSERT INTO t5106.node VALUES ( 1, NULL, 'POINT(0 0)' );
-- Cannot reference non-existing faces w/out dropping
-- these constraints
ALTER TABLE t5106.edge_data DROP constraint left_face_exists;
ALTER TABLE t5106.edge_data DROP constraint right_face_exists;
INSERT INTO t5106.edge VALUES
(
	1, -- edge_id
	1, 1, -- start/end node
	1, -1, -- next left/right edge
	1, 2, -- left/right faces (different, both non-0 and non existent)
  'LINESTRING(0 0,10 0,10 10,0 0)'
);
DO $BODY$
BEGIN
	PERFORM topology.ST_RemEdgeNewFace('t5106', 1);
	RAISE EXCEPTION '#5106 failed throwing an exception';
EXCEPTION WHEN OTHERS THEN
	RAISE EXCEPTION '#5106 threw: %', SQLERRM;
END;
$BODY$ LANGUAGE 'plpgsql';
ROLLBACK;

----------------------------
-- Clean up
----------------------------

DROP FUNCTION save_edges();
DROP FUNCTION check_edges(text);
DROP FUNCTION save_faces();
DROP FUNCTION check_faces(text);
DROP FUNCTION save_nodes();
DROP FUNCTION check_nodes(text);
DROP FUNCTION catch_error(text);
