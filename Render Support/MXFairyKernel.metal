//
//  MXFairyKernel.metal
//  Metal
//
//  Created by William Woody on 1/5/19.
//  Copyright © 2019 Glenview Software. All rights reserved.
//

#include <metal_stdlib>
#include "MXShaderTypes.h"

using namespace metal;


/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	fairy_kernel
 *
 *		Sample kernel which calculates the position of all our fairy lights..
 */

kernel void fairy_kernel(device MXFairyLocation *positions [[buffer(MXVertexIndexLocations)]],
						 constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]],
						 uint ix [[thread_position_in_grid]])
{
	device MXFairyLocation *loc = positions + ix;

	float a = loc->angle[0] + loc->speed * u.elapsed;

	float sx = sin(a);
	float cx = cos(a);
	float sy = sin(loc->angle[1]);
	float cy = cos(loc->angle[1]);

	loc->position = float3(cx * cy * loc->radius,
						   sy * loc->radius,
						   sx * cy * loc->radius);
}
