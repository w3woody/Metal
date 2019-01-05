//
//  MXGeometry.h
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#ifndef MXGeometry_h
#define MXGeometry_h

#include <simd/simd.h>

/****************************************************************************/
/*																			*/
/*	Geometry Structures														*/
/*																			*/
/****************************************************************************/

/*
 *	IMPORTANT: The format of the structures here must match the structure
 *	declarations in the Metal shader file. The reason why they are not
 *	declared in common is so we can show the use of the attributes parameter
 *	on the vertex shader.
 *
 *	An alternate way to do this--using a common structure and using a
 *	vertex index to iterate through the array of vertices in the GPU is
 *	shown in the Apple "Hello Triangle" example located at
 *
 *		https://developer.apple.com/documentation/metal/hello_triangle?language=objc
 */

/*	MTVertex
 *
 *		The structure of a vertex. We use a 4D coordinate for the vertex
 *	location, with a homogeneous coordinate (x,y,z,w). For a quick primer
 *	in homogeneous coordinates, there are a number of overviews that can
 *	be found on the Internet, including a quick introduction at Wikipedia
 *	here:
 *
 *		https://en.wikipedia.org/wiki/Homogeneous_coordinates#Use_in_computer_graphics_and_computer_vision
 */

typedef struct MXVertex
{
	vector_float3 position;
	vector_float3 normal;
	vector_float2 texture;
} MXVertex;

/*	MXFairyVertex
 *
 *		The structure of our fairy lights
 */

typedef struct MXFairyVertex
{
	vector_float2 position;
} MXFairyVertex;


#endif /* MXGeometry_h */
