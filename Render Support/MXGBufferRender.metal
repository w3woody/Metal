//
//  MXGBufferRender.metal
//  Metal
//
//  Created by William Woody on 1/3/19.
//  Copyright © 2019 Glenview Software. All rights reserved.
//

#include <metal_stdlib>
#include "MXShaderTypes.h"

using namespace metal;

/*
 *	This version of our shaders does the second half of taking our color,
 *	shadow, depth and normal information and carrying out the lighting
 *	effects.
 *
 *	Because our work is all done in the fragment shader function, our
 *	vertex function is dirt stupid simple.
 */

/****************************************************************************/
/*																			*/
/*	Geometry Structures														*/
/*																			*/
/****************************************************************************/

struct VertexIn {
    float2 position		[[attribute(MXAttributeIndexPosition)]];
};

struct VertexOut {
	float4 position 	[[position]];
	float2 uv;
	float2 xy;
};

/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_grender
 *
 *		The main vertex shader function used by our GPU. Here is where we would
 *	do geometry transformation options--but in our case we simply pass through
 *	our geometry.
 */

vertex VertexOut vertex_grender(VertexIn v [[stage_in]])
{
	VertexOut out;

	out.position = float4(v.position,0,1);
	out.xy = v.position;

	/*
	 *	Compute texture x/y. Note we should be invoked without a perspective
	 *	matrix, so w == 1.
	 *
	 *	This transforms our position map from [-1,1],[-1,1] to [0,1][0,1]
	 *	with a change in origin.
	 */

	out.uv = float2((1 + v.position.x)/2,(1 - v.position.y)/2);

	return out;
}

/*	fragment_grender
 *
 *		This fragment shader actually does the light calculations based on
 *	the input gbuffer data
 */

constant float3 lightColor(1,1,1);
constant float ambientIntensity = 0.1;
constant float3 lightDirection(1,0,1);
constant float3 eyeDirection(0,0,1);
constant float specularTightness = 25;
constant float specularIntensity = 0.75;


fragment float4 fragment_grender(VertexOut v [[stage_in]],
							     texture2d<float, access::sample> color [[texture(MXTextureIndexColor)]],
							     texture2d<float, access::sample> normal [[texture(MXTextureIndexNormal)]],
							     depth2d<float, access::sample> depth [[texture(MXTextureIndexDepth)]])
{
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);


	/*
	 *	Get the color and run our color calculations for our basic
	 *	lighting effects
	 */

	const float3 normalLight = normalize(lightDirection);
	const float3 normalEye = normalize(eyeDirection);

	/*
	 *	Get our values from the gbuffer for lighting calculations
	 */

	float3 teapotColor = color.sample(linearSampler,v.uv).rgb;
	float shadow = color.sample(linearSampler,v.uv).a;
	float3 teapotNormal = normalize(normal.sample(linearSampler,v.uv).xyz);


	/*
	 *	Calculate lighting effects for primary lighting
	 */

	// Ambient lighting
	float4 ambient = float4(teapotColor * lightColor * ambientIntensity,1.0);

	// Diffuse lighting
	float dotprod = dot(teapotNormal,normalLight);
	float diffuseIntensity = clamp(dotprod,0,1) * shadow;
	float4 diffuse = float4(teapotColor * lightColor * diffuseIntensity,1.0);

	// Specular lighting
	float3 refl = (2 * dotprod) * teapotNormal - normalLight;
	float specIntensity = dot(refl,normalEye);
	specIntensity = clamp(specIntensity,0,1);
	specIntensity = powr(specIntensity,specularTightness) * shadow;
	float4 specular = float4(lightColor * specIntensity * specularIntensity,1.0);

	return ambient + diffuse + specular;
}

