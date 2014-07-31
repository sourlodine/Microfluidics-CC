/*
 * ls-obstacle.h
 *
 *  Created on: Jul 31, 2014
 *      Author: kirill
 */

#ifndef LS_OBSTACLE_H_
#define LS_OBSTACLE_H_

#include <vector>
#include <utility>
#include <string>

class FunnelObstacle
{
  struct Grid
  {
    float data[64][64]; // YX
  };
  Grid m_grid;

  float m_yPlaneUp, m_yPlaneDown, m_y0;

  std::vector< std::pair <float, float> > m_interface;
  void initInterface();

  float calcDist(const float x, const float y) const;

  bool insideBB(const float x, const float y) const;

public:

  FunnelObstacle(const float length);

  bool isInside(const float x, const float y) const;
  std::pair<bool, float> sample(const float x, const float y) const;

  void write(const std::string& fileName) const;
  void read(const std::string& fileName);
};


#endif /* LS_OBSTACLE_H_ */
