#pragma once

#include <mirheo/core/interactions/interface.h>
#include <mirheo/core/interactions/parameters_wrap.h>

namespace mirheo
{

/** \brief Base class for short-range symmetric pairwise interactions
 */
class BasePairwiseInteraction : public Interaction
{
public:

    /** \brief Construct a base pairwise interaction from parameters.
        \param [in] state The global state of the system.
        \param [in] name The name of the interaction.
        \param [in] rc The cutoff radius of the interaction. 
                       Must be positive and smaller than the sub-domain size.
    */
    BasePairwiseInteraction(const MirState *state, const std::string& name, real rc);

    /** \brief Construct the interaction from a snapshot.
        \param [in] state The global state of the system.
        \param [in] loader The \c Loader object. Provides load context and unserialization functions.
        \param [in] config The parameters of the interaction.
     */
    BasePairwiseInteraction(const MirState *state, Loader& loader, const ConfigObject& config);
    ~BasePairwiseInteraction();
    
    virtual void setSpecificPair(const std::string& pv1name, const std::string& pv2name, const ParametersWrap::MapParams& mapParams) = 0;

    real getCutoffRadius() const override;

protected:
    real rc_; ///< cut-off radius of the interaction
};

} // namespace mirheo
